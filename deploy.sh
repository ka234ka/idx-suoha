#!/bin/bash
# ==============================================
# CloudProxy 部署脚本（IDX / VPS 通用）
# - 支持 apt / yum / nix-env
# - 固定端口 2546
# - systemd 自启守护
# - 无 systemd 用 nohup + crontab 自启
# ==============================================

set -euo pipefail

APP_NAME="cloudproxy"
INSTALL_DIR="$HOME/${APP_NAME}"
PORT=2546
REPO_URL="https://raw.githubusercontent.com/ka234ka/idx-suoha/main"
SERVICE_NAME="${APP_NAME}.service"

# ===== 检查 sudo =====
SUDO=""
if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
fi

log() {
    echo -e "[$(date '+%F %T')] $1"
}

log "[1/6] 检查并安装依赖..."
PKGS=(curl wget unzip tar lsof)

if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update -y
    $SUDO apt-get install -y "${PKGS[@]}"
elif command -v yum >/dev/null 2>&1; then
    $SUDO yum install -y "${PKGS[@]}"
elif command -v nix-env >/dev/null 2>&1; then
    nix-env -iA nixpkgs.curl nixpkgs.wget nixpkgs.unzip nixpkgs.gnutar nixpkgs.lsof
else
    log "❌ 未检测到支持的包管理器，请手动安装: ${PKGS[*]}"
    exit 1
fi

log "[2/6] 创建部署目录: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

log "[3/6] 下载程序与配置..."
curl -fsSL "$REPO_URL/cloudproxy" -o "$INSTALL_DIR/cloudproxy" || log "⚠️ 未找到 cloudproxy"
curl -fsSL "$REPO_URL/config.json" -o "$INSTALL_DIR/config.json" || log "⚠️ 未找到 config.json"
chmod +x "$INSTALL_DIR/cloudproxy"

log "[4/6] 配置启动方式..."
if command -v systemctl >/dev/null 2>&1; then
    log "检测到 systemd，可用 systemd 守护进程"
    $SUDO tee /etc/systemd/system/${SERVICE_NAME} >/dev/null <<EOF
[Unit]
Description=CloudProxy Service
After=network.target

[Service]
ExecStart=${INSTALL_DIR}/cloudproxy --config ${INSTALL_DIR}/config.json --port ${PORT}
Restart=always
RestartSec=3
User=${USER}
WorkingDirectory=${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
EOF

    log "[5/6] 启动并设置开机自启..."
    $SUDO systemctl daemon-reload
    $SUDO systemctl enable ${SERVICE_NAME}
    $SUDO systemctl restart ${SERVICE_NAME}
else
    log "⚠️ 无 systemd，使用 nohup + crontab 自启动"
    nohup "${INSTALL_DIR}/cloudproxy" --config "${INSTALL_DIR}/config.json" --port ${PORT} >/tmp/${APP_NAME}.log 2>&1 &
    # 添加开机自启
    (crontab -l 2>/dev/null; echo "@reboot nohup ${INSTALL_DIR}/cloudproxy --config ${INSTALL_DIR}/config.json --port ${PORT} >/tmp/${APP_NAME}.log 2>&1 &") | crontab -
fi

log "[6/6] 健康检查..."
sleep 2
if lsof -i :$PORT >/dev/null 2>&1; then
    log "✅ 服务已在端口 $PORT 运行"
else
    log "❌ 服务启动失败，请检查日志"
fi

log "🎯 部署完成"


