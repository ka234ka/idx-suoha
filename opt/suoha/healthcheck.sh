#!/usr/bin/env bash
set -e
PORT_FILE="$(dirname "$0")/port.txt"
if [ ! -f "$PORT_FILE" ]; then
    PORT=2546
else
    PORT=$(cat "$PORT_FILE")
fi

if ! nc -z 127.0.0.1 "$PORT"; then
    echo "$(date): 端口 $PORT 无响应，重启服务..."
    pkill -f run.sh || true
    nohup "$(dirname "$0")/run.sh" > "$(dirname "$0")/suoha.log" 2>&1 &
else
    echo "$(date): 服务正常运行中"
fi
