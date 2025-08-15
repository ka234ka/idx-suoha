#!/bin/bash
set -euo pipefail

# ====== 全局配置 ======
PORT=2546
STATE_FILE="/root/deploy_state.log"
CF_TOKEN_FILE="/root/.cf_token"
WORK_DIR="$HOME/assa"
LOG_FILE="$WORK_DIR/deploy.log"

log() {
    echo -e "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"
}

log "🚀 开始部署..."

# ====== 检查环境 ======
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

if ! command -v curl >/dev/null 2>&1; then
    log "安装 curl..."
    apt-get update && apt-get install -y curl || yum install -y curl
fi

if ! command -v unzip >/dev/null 2>&1; then
    log "安装 unzip..."
    apt-get update && apt-get install -y unzip || yum install -y unzip
fi

# ====== 检测 systemd 是否存在 ======
if command -v systemctl >/dev/null 2>&1; then
    HAS_SYSTEMD=true
else
    HAS_SYSTEMD=false
fi
log "systemd 可用: $HAS_SYSTEMD"

# ====== 安装 xray-core ======
install_xray() {
    log "下载并安装 xray-core..."
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip
    unzip -o xray.zip -d xray-core
    mv xray-core /usr/local/bin/xray
    chmod +x /usr/local/bin/xray/xray
}

if ! command -v /usr/local/bin/xray/xray >/dev/null 2>&1; then
    install_xray
else
    log "xray-core 已存在，跳过安装。"
fi

# ====== 生成配置 ======
cat > "$WORK_DIR/config.json" <<EOF
{
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$(uuidgen)",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

log "生成配置完成: $WORK_DIR/config.json"

# ====== 启动与守护 ======
start_service() {
    if $HAS_SYSTEMD; then
        log "创建 systemd 服务..."
        cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xray/xray run -c $WORK_DIR/config.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable --now xray
    else
        log "使用 nohup 启动..."
        nohup /usr/local/bin/xray/xray run -c "$WORK_DIR/config.json" >> "$LOG_FILE" 2>&1 &
        (crontab -l 2>/dev/null; echo "@reboot nohup /usr/local/bin/xray/xray run -c '$WORK_DIR/config.json' >> '$LOG_FILE' 2>&1 &") | crontab -
    fi
}

start_service

# ====== Cloudflare Tunnel ======
if [ -f "$CF_TOKEN_FILE" ]; then
    log "检测到 Cloudflare Tunnel token，启动自动重连..."
    nohup cloudflared tunnel --edge-ip-version auto run --token "$(cat $CF_TOKEN_FILE)" >> "$LOG_FILE" 2>&1 &
    (crontab -l 2>/dev/null; echo "@reboot nohup cloudflared tunnel --edge-ip-version auto run --token '$(cat $CF_TOKEN_FILE)' >> '$LOG_FILE' 2>&1 &") | crontab -
else
    log "⚠ 未检测到 Cloudflare token，跳过隧道配置。"
fi

# ====== 保存部署状态 ======
echo "部署完成于 $(date)" > "$STATE_FILE"

log "✅ 部署完成"
log "VLESS 端口: $PORT"

