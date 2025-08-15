#!/usr/bin/env bash
set -Eeuo pipefail
source /opt/suoha/env
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"
exec bash -lc "$APP_CMD"
