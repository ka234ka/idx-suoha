#!/usr/bin/env bash
set -Eeuo pipefail
source /opt/suoha/env
HOST="127.0.0.1"
TIMEOUT=3

tcp_ok=1
if command -v nc >/dev/null 2>&1; then
  if nc -z -w "$TIMEOUT" "$HOST" "$PORT"; then tcp_ok=0; fi
else
  if timeout "$TIMEOUT" bash -c "echo > /dev/tcp/${HOST}/${PORT}" 2>/dev/null; then tcp_ok=0; fi
fi

if [[ $tcp_ok -ne 0 ]]; then
  echo "[HEALTH] 端口 ${PORT} 不可达，重启服务..."
  systemctl restart suoha || true
  exit 1
fi

echo "[HEALTH] OK: ${HOST}:${PORT}"
