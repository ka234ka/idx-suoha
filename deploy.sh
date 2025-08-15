#!/bin/bash
# ==============================================
# 部署脚本 for IDX / VPS
# - 支持 apt / yum / nix-env
# - 固定端口 2546
# - systemd 后台守护 + 自愈
# - LF 格式，防止 bash\r 报错
# ==============================================

set -euo pipefail

APP_NAME="cloudproxy"
INSTALL_DIR="/opt/${APP_NAME}"
PORT=2546
REPO_URL="https://raw.githubusercontent.com/ka234ka/idx-suoha/main"
SERVICE_NAME="${APP_NAME}.service"

echo "[1/6] 检查并安装依赖..."
PKGS=(curl wget unzip tar lsof)

if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y "${PKGS[@]}"
elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y "${PKGS[@]}"
elif command -v nix-env >/dev/null 2>&1; then
    nix-env -iA nixpkgs.curl nixpkgs.wget nixpkgs.unzip nixpkgs.gnutar nixpkgs.lsof
else
    echo "❌ 未检测到支持的包管理器，请手动安装: ${PKGS[*]}"
    exit 1
fi

echo "[2/6] 创建部署目录: $INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR"
sudo chown "$USER":"$USER" "$INSTALL_DIR"

echo "[3/6] 下载程序与配置..."
# 这里假设你有 cloudproxy 可执行文件和 config.json
curl -fsSL "$REPO_URL/cloudproxy" -o "$INSTALL_DIR/cloudproxy"
curl -fsSL "$REPO_URL/config.json" -o "$INSTALL_DIR/config.json"

chmod +x "$INSTALL_DIR/cloudproxy"

echo "[4/6] 创建 systemd 服务..."
sudo tee /etc/systemd/system/${SERVICE_NAME} >/dev/null <<EOF
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

echo "[5/6] 启动并设置开机自启..."
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}
sudo systemctl restart ${SERVICE_NAME}

echo "[6/6] 健康检查..."
sleep 2
if lsof -i :$PORT >/dev/null 2>&1; then
    echo "✅ 服务已在端口 $PORT 运行，并已设置开机自启"
else
    echo "❌ 服务启动失败，请使用: sudo journalctl -u ${SERVICE_NAME} -f 查看日志"
fi

echo "🎯 部署完成"


