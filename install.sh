#!/usr/bin/env bash
set -e

APP_DIR="/opt/suoha"

echo "[1/4] 复制脚本到 $APP_DIR"
sudo mkdir -p "$APP_DIR"
sudo cp -r opt/suoha/* "$APP_DIR/"
sudo chmod +x "$APP_DIR"/*.sh

if command -v systemctl >/dev/null 2>&1; then
    echo "[2/4] 检测到 systemd，安装 unit 文件..."
    sudo cp systemd/* /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable suoha suoha-health.timer
    sudo systemctl start suoha suoha-health.timer
    echo "✅ systemd 服务已启动"
else
    echo "[2/4] 未检测到 systemd，采用 nohup + cron 保活"
    pkill -f "$APP_DIR/run.sh" || true
    nohup "$APP_DIR/run.sh" > "$APP_DIR/suoha.log" 2>&1 &
    ( crontab -l 2>/dev/null | grep -v "$APP_DIR/healthcheck.sh" ; \
      echo "* * * * * $APP_DIR/healthcheck.sh" ) | crontab -
    echo "✅ 无 systemd 环境部署完成"
fi

