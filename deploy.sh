#!/usr/bin/env bash
set -euo pipefail

# ====== 全局配置 ======
PORT=2546
WORK_DIR="$HOME/assa"
STATE_FILE="$WORK_DIR/deploy_state.log"
CF_TOKEN_FILE="$HOME/.cf_token"
LOG_FILE="$WORK_DIR/deploy.log"

log() {
    echo -e "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"
}

log "🚀 开始部署..."

# ====== 创建工作目录 ======
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ====== 检查基础依赖 ======
install_pkg() {
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y "$@"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "$@"
    else
        log "❌ 不支持的包管理器"
        exit 1
    fi
}

for pkg in curl unzip; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
        log "安装 $pkg..."
        install_pkg "$pkg"
    fi
done

# ====== 检测 systemd ======
if command -v systemctl >/dev/null 2>&1; then
    HAS_SYSTEMD=true
else
    HAS_SYSTEMD=false
fi
log "systemd 可用: $HAS_SYSTEMD"

# ====== 安装 Xray-Core ======
install_xray() {
    log "下载并安装 Xray-Core..."
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip
    unzip -o xray.zip
    install xray /usr/local/bin/xray
    rm -f xray.zip xray
}

if ! command -v /usr/local/bin/xray >/dev/null 2>&1; then
    install_xray
else
    log "Xray-Core 已存在，跳过安装。"
fi

# ====== 生成配置 ======
UUID_GEN=$(uuidgen)
cat > "$WORK_DIR/config.json" <<EOF
{
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID_GEN",
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

log "配置生成完成: $WORK_DIR/config.json"

# ====== 启动 Xray ======
start_xray() {
    if $HAS_SYSTEMD; then
        log "创建 systemd 服务..."
        cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xray run -c $WORK_DIR/config.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable --now xray
    else
        log "使用 nohup 后台运行..."
        nohup /usr/local/bin/xray run -c "$WORK_DIR/config.json" >> "$LOG_FILE" 2>&1 &
        (crontab -l 2>/dev/null; echo "@reboot nohup /usr/local/bin/xray run -c '$WORK_DIR/config.json' >> '$LOG_FILE' 2>&1 &") | crontab -
    fi
}

start_xray

# ====== 启动 Cloudflare Tunnel（可选） ======
if [[ -f "$CF_TOKEN_FILE" ]]; then
    log "检测到 CF Token，启动隧道..."
    nohup cloudflared tunnel --edge-ip-version auto run --token "$(cat "$CF_TOKEN_FILE")" >> "$LOG_FILE" 2>&1 &
    (crontab -l 2>/dev/null; echo "@reboot nohup cloudflared tunnel --edge-ip-version auto run --token '$(cat "$CF_TOKEN_FILE")' >> '$LOG_FILE' 2>&1 &") | crontab -
else
    log "⚠ 未检测到 CF Token，跳过隧道配置。"
fi

# ====== 保存部署状态 ======
echo "部署完成于 $(date)" > "$STATE_FILE"

log "✅ 部署完成"
log "VLESS 端口: $PORT"
log "UUID: $UUID_GEN"



