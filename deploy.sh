#!/usr/bin/env bash
# Integrated IDX deployer with CF tunnel auto-reconnect

# 开启严格模式，如果 shell 不支持 pipefail 则自动降级
set -Eeuo pipefail 2>/dev/null || set -Eeuo

# ---------------------------
# Config
# ---------------------------
REPO_URL="${REPO_URL:-https://github.com/ka234ka/idx-suoha.git}"
APP_DIR="${APP_DIR:-$HOME/suoha}"
OPT_DIR="$APP_DIR/opt/suoha"
LOG_FILE="$APP_DIR/suoha.log"
WATCHDOG="$APP_DIR/watchdog.sh"
CF_LOG="$APP_DIR/cloudflared.log"
PORT_DEFAULT="2546"

# ---------------------------
# Helpers
# ---------------------------
log()   { printf "\033[32m%s\033[0m\n" "$*"; }   # green
warn()  { printf "\033[33m%s\033[0m\n" "$*"; }   # yellow
err()   { printf "\033[31m%s\033[0m\n" "$*"; }   # red

on_error() {
  err "部署失败：第 ${BASH_LINENO[0]} 行出错。检查日志：$LOG_FILE 与 $CF_LOG（若启用 CF）"
}
trap on_error ERR

ensure_path() {
  export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
}

kill_if_running() {
  local pat="$1"
  pgrep -f "$pat" >/dev/null 2>&1 && pkill -f "$pat" || true
}

read_port() {
  local port="$PORT_DEFAULT"
  if [[ -f "$OPT_DIR/env" ]]; then
    # shellcheck disable=SC1090
    source "$OPT_DIR/env" || true
  fi
  if [[ -n "${PORT:-}" ]]; then
    port="$PORT"
  elif [[ -f "$OPT_DIR/port.txt" ]]; then
    port="$(cat "$OPT_DIR/port.txt" 2>/dev/null || true)"
  fi
  echo "${port:-$PORT_DEFAULT}"
}

write_defaults_if_missing() {
  mkdir -p "$OPT_DIR"
  # Default env/port
  if [[ ! -f "$OPT_DIR/port.txt" ]]; then echo "$PORT_DEFAULT" > "$OPT_DIR/port.txt"; fi
  if [[ ! -f "$OPT_DIR/env" ]]; then printf "PORT=%s\n" "$PORT_DEFAULT" > "$OPT_DIR/env"; fi
  chmod 600 "$OPT_DIR/env" || true

  # Minimal run.sh fallback (only if missing)
  if [[ ! -f "$OPT_DIR/run.sh" ]]; then
    cat > "$OPT_DIR/run.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail 2>/dev/null || set -Eeuo
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load env
if [[ -f "$BASE_DIR/env" ]]; then
  # shellcheck disable=SC1090
  source "$BASE_DIR/env"
fi

# Resolve PORT
if [[ -z "${PORT:-}" ]]; then
  if [[ -f "$BASE_DIR/port.txt" ]]; then
    PORT="$(cat "$BASE_DIR/port.txt")"
  else
    PORT="2546"
  fi
fi

# If APP_CMD provided, exec it; otherwise fallback to http.server
if [[ -n "${APP_CMD:-}" ]]; then
  echo "启动自定义应用: $APP_CMD"
  exec bash -lc "$APP_CMD"
else
  echo "启动 suoha 基础服务，监听端口: $PORT"
  exec python3 -m http.server "$PORT" --bind 0.0.0.0
fi
EOF
    chmod +x "$OPT_DIR/run.sh"
  fi

  # Minimal healthcheck fallback (only if missing)
  if [[ ! -f "$OPT_DIR/healthcheck.sh" ]]; then
    cat > "$OPT_DIR/healthcheck.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail 2>/dev/null || set -Eeuo
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOME/suoha/suoha.log"

# Load env + resolve PORT
if [[ -f "$BASE_DIR/env" ]]; then
  # shellcheck disable=SC1090
  source "$BASE_DIR/env"
fi
if [[ -z "${PORT:-}" ]]; then
  if [[ -f "$BASE_DIR/port.txt" ]]; then
    PORT="$(cat "$BASE_DIR/port.txt")"
  else
    PORT="2546"
  fi
fi

# Check listening by curl/nc
check_ok=1
if command -v curl >/dev/null 2>&1; then
  curl -fsS "http://127.0.0.1:${PORT}/" >/dev/null 2>&1 && check_ok=0 || check_ok=1
elif command -v nc >/dev/null 2>&1; then
  nc -z 127.0.0.1 "${PORT}" >/dev/null 2>&1 && check_ok=0 || check_ok=1
fi

if [[ "$check_ok" -ne 0 ]]; then
  echo "$(date +'%F %T') 健康检查失败，尝试重启服务..." >> "$LOG_FILE"
  pgrep -f "$BASE_DIR/run.sh" >/dev/null 2>&1 && pkill -f "$BASE_DIR/run.sh" || true
  nohup "$BASE_DIR/run.sh" >> "$LOG_FILE" 2>&1 &
  sleep 1
  echo "$(date +'%F %T') 已触发重启" >> "$LOG_FILE"
fi
EOF
    chmod +x "$OPT_DIR/healthcheck.sh"
  fi
}

install_cron_or_watchdog() {
  if command -v crontab >/dev/null 2>&1; then
    ( crontab -l 2>/dev/null | grep -v "$OPT_DIR/healthcheck.sh" ; \
      echo "* * * * * $OPT_DIR/healthcheck.sh # suoha-healthcheck" ) | crontab -
    log "已安装 cron 健康检查（每分钟）"
    kill_if_running "$WATCHDOG"
  else
    cat > "$WATCHDOG" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail 2>/dev/null || set -Eeuo
while true; do
  "$OPT_DIR/healthcheck.sh" || true
  sleep 60
done
EOF
    chmod +x "$WATCHDOG"
    nohup "$WATCHDOG" >/dev/null 2>&1 &
    log "未检测到 crontab，已启用看门狗循环保活"
  fi
}

verify_service() {
  local port="$(read_port)"
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp | grep -E ":${port}\\b" || warn "端口 ${port} 未在 ss 输出中发现（可能仍在启动中）"
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -I --max-time 3 "http://127.0.0.1:${port}" || warn "curl 连通性检查失败（可能是 404 也算通路）"
  else
    command -v nc >/dev/null 2>&1 && nc -zv 127.0.0.1 "${port}" || true
  fi
}

detect_arch_asset() {
  local arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo "cloudflared-linux-amd64" ;;
    aarch64|arm64) echo "cloudflared-linux-arm64" ;;
    *) echo "cloudflared-linux-amd64" ;;
  esac
}

ensure_cloudflared() {
  if command -v cloudflared >/dev/null 2>&1; then return 0; fi
  log "未检测到 cloudflared，正在下载..."
  mkdir -p "$HOME/.local/bin"
  local asset; asset="$(detect_arch_asset)"
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/${asset}" -o "$HOME/.local/bin/cloudflared"
  chmod +x "$HOME/.local/bin/cloudflared"
  ensure_path
  command -v cloudflared >/dev/null 2>&1 || { err "cloudflared 安装失败"; exit 1; }
}

start_service() {
  kill_if_running "$OPT_DIR/run.sh"
  nohup "$OPT_DIR/run.sh" > "$LOG_FILE" 2>&1 &
  sleep 0.8
}

start_cloudflared_if_token() {
  if [[ -z "${CF_TUNNEL_TOKEN:-}" ]]; then
    warn "未检测到 CF_TUNNEL_TOKEN，跳过 Cloudflare 隧道启动"
    return 0
  fi
  kill_if_running "cloudflared tunnel"
  ensure_cloudflared
  : > "$CF_LOG" || true
  log "启动 Cloudflare 隧道..."
  nohup cloud

