#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1) 尝试加载环境变量
if [[ -f "$BASE_DIR/env" ]]; then
  # shellcheck disable=SC1090
  source "$BASE_DIR/env"
fi

# 2) 端口回退序列：env -> port.txt -> 默认 2546
if [[ -z "${PORT:-}" ]]; then
  if [[ -f "$BASE_DIR/port.txt" ]]; then
    PORT="$(cat "$BASE_DIR/port.txt")"
  else
    PORT=2546
  fi
fi

echo "启动 suoha 服务，监听端口: $PORT"
exec python3 -m http.server "$PORT" --bind 0.0.0.0
