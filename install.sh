
### install.sh
```bash
#!/usr/bin/env bash
# 安装器：复制文件到系统路径，安装依赖，开放防火墙，配置并启动 systemd 与健康检查
set -Eeuo pipefail

# ------------ 常量 ------------
readonly PORT=2546
readonly SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly OPT_DST="/opt/suoha"
readonly SVC_DST="/etc/systemd/system"
readonly ENV_FILE="${OPT_DST}/env"
readonly PORT_FILE="${OPT_DST}/port.txt"
readonly RUN_FILE="${OPT_DST}/run.sh"
readonly HEALTH_FILE="${OPT_DST}/healthcheck.sh"
readonly SERVICE_NAME="suoha"

log()   { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" 1>&2; }
trap 'error "失败于行 $LINENO: $BASH_COMMAND"' ERR

need_root() {
  if [[ $EUID -ne 0 ]]; then
    error "请以 root 运行（或在命令前加 sudo）。"
    exit 1
  fi
}

detect_pkg() {
  if command -v apt-get >/dev/null 2>&1; then echo apt; return; fi
  if command -v dnf >/dev/null 2>&1; then echo dnf; return; fi
  if command -v yum >/dev/null 2>&1; then echo yum; return; fi
  if command -v pacman >/dev/null 2>&1; then echo pacman; return; fi
  echo unknown
}

pkg_install() {
  local pkmgr; pkmgr=$(detect_pkg)
  case "$pkmgr" in
    apt)
      apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y curl jq tar python3 ca-certificates iproute2 netcat-openbsd
      ;;
    dnf) dnf install -y curl jq tar python3 ca-certificates iproute iproute-tc nmap-ncat ;;
    yum) yum install -y curl jq tar python3 ca-certificates iproute nmap-ncat ;;
    pacman)
      pacman -Sy --noconfirm curl jq tar python3 ca-certificates iproute2 ncat
      ;;
    *)
      warn "未识别包管理器，跳过依赖安装；请确保已有 curl/jq/python3/iproute2/netcat。"
      ;;
  esac
}

port_in_use() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp | awk -v p="$PORT" '$4 ~ ":"p"$" {print; found=1} END{exit (found?0:1)}'
    return $?
  fi
  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1 && return 0
  fi
  return 1
}

check_port_conflict() {
  if port_in_use; then
    error "端口 $PORT 已被占用，请先释放或修改占用进程后再安装。"
    if command -v ss >/dev/null 2>&1; then
      ss -ltnp | grep ":${PORT}\b" || true
    fi
    exit 1
  fi
}

copy_files() {
  mkdir -p "$OPT_DST"
  install -m 0644 "${SRC_DIR}/opt/suoha/env" "$ENV_FILE"
  install -m 0644 "${SRC_DIR}/opt/suoha/port.txt" "$PORT_FILE"
  install -m 0755 "${SRC_DIR}/opt/suoha/run.sh" "$RUN_FILE"
  install -m 0755 "${SRC_DIR}/opt/suoha/healthcheck.sh" "$HEALTH_FILE"

  # 强制固定端口为 2546（覆盖 env 中的 PORT）
  if grep -q '^PORT=' "$ENV_FILE"; then
    sed -i "s/^PORT=.*/PORT=${PORT}/" "$ENV_FILE"
  else
    echo "PORT=${PORT}" >> "$ENV_FILE"
  fi
  echo "$PORT" > "$PORT_FILE"

  # systemd 单元
  install -m 0644 "${SRC_DIR}/systemd/suoha.service" "${SVC_DST}/suoha.service"
  install -m 0644 "${SRC_DIR}/systemd/suoha-health.service" "${SVC_DST}/suoha-health.service"
  install -m 0644 "${SRC_DIR}/systemd/suoha-health.timer" "${SVC_DST}/suoha-health.timer"

  # 调整 service 文件中的路径（如果需要）
  sed -i "s|^ExecStart=.*|ExecStart=${RUN_FILE}|" "${SVC_DST}/suoha.service"
  sed -i "s|^EnvironmentFile=.*|EnvironmentFile=${ENV_FILE}|" "${SVC_DST}/suoha.service"
  sed -i "s|^ExecStart=.*|ExecStart=${HEALTH_FILE}|" "${SVC_DST}/suoha-health.service"
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "Status: active"; then
      ufw allow "${PORT}/tcp" || true
      log "UFW 已放行 TCP ${PORT}"
    fi
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port="${PORT}/tcp" || true
    firewall-cmd --reload || true
    log "firewalld 已放行 TCP ${PORT}"
  fi
  if command -v iptables >/dev/null 2>&1; then
    if ! iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
      iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT || true
      log "iptables 已放行 TCP ${PORT}"
    fi
  fi
}

enable_services() {
  systemctl daemon-reload
  systemctl enable --now suoha
  systemctl enable --now suoha-health.timer
}

post_info() {
  log "安装完成。当前监听端口固定为：\033[1;32m${PORT}\033[0m"
  log "环境与端口文件：${ENV_FILE}，${PORT_FILE}"
  log "查看状态：systemctl status suoha"
  log "查看日志：journalctl -u suoha -e -n 200 --no-pager"
  log "健康定时器：systemctl status suoha-health.timer"
}

main() {
  need_root
  pkg_install
  check_port_conflict
  copy_files
  open_firewall
  enable_services
  post_info
}

main "$@"
