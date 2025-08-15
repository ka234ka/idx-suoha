#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/ka4ka/idx-suoha.git"
APP_DIR="$HOME/suoha"
OPT_DIR="$APP_DIR/opt/suoha"
LOG_FILE="$APP_DIR/suoha.log"
WATCHDOG="$APP_DIR/watchdog.sh"

echo "[1/6] 克隆或更新仓库..."
if [[ -d "$APP_DIR/.git" ]]; then
  git -C "$APP_DIR" pull --rebase --autostash
else
  git clone "$REPO_URL" "$APP_DIR"
fi

echo "[2/6] 准备运行环境..."
mkdir -p "$OPT_DIR"
chmod +x "$OPT_DIR"/*.sh || true
# 确保存在端口与 env（固定 2546）
if [[ ! -f "$OPT_DIR/port.txt" ]]; then echo 2546 > "$OPT_DIR/port.txt"; fi
if [[ ! -f "$OPT_DIR/env" ]]; then echo "PORT=2546" > "$OPT_DIR/env"; fi

# 导出 PATH，避免非登录 shell PATH 不全
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

echo "[3/6] 停止旧进程..."
# 仅杀当前项目的 run.sh 进程
pgrep -f "$OPT_DIR/run.sh" >/dev/null 2>&1 && pkill -f "$OPT_DIR/run.sh" || true
# 同时停止旧的看门狗
pgrep -f "$WATCHDOG" >/dev/null 2>&1 && pkill -f "$WATCHDOG" || true

echo "[4/6] 后台启动服务（nohup）..."
nohup "$OPT_DIR/run.sh" > "$LOG_FILE" 2>&1 &
sleep 0.8

echo "[5/6] 健康检查保活..."
if command -v crontab >/dev/null 2>&1; then
  # 安装每分钟健康检查
  ( crontab -l 2>/dev/null | grep -v "$OPT_DIR/healthcheck.sh" ; \
    echo "* * * * * $OPT_DIR/healthcheck.sh" ) | crontab -
  echo "已安装 cron 健康检查"
else
  # 无 crontab：用看门狗循环替代
  cat > "$WATCHDOG" <<EOF
#!/usr/bin/env bash
set -e
while true; do
  "$OPT_DIR/healthcheck.sh" || true
  sleep 60
done
EOF
  chmod +x "$WATCHDOG"
  nohup "$WATCHDOG" >/dev/null 2>&1 &
  echo "未检测到 crontab，已启用看门狗循环"
fi

echo "[6/6] 验证基本可用性..."
if command -v ss >/dev/null 2>&1; then
  ss -ltnp | grep -E ":2546\\b" || true
fi

echo "✅ 部署完成"
echo "- 代码目录: $APP_DIR"
echo "- 日志：tail -f $LOG_FILE"
echo "- 本地连通：curl -I http://127.0.0.1:2546 || nc -zv 127.0.0.1 2546"
