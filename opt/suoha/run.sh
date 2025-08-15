#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
echo "启动 suoha 服务，监听端口: $PORT"
# TODO: 这里替换成你真实的 Reality / VLESS / VMess 启动命令
python3 -m http.server "$PORT"
