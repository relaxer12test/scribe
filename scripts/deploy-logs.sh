#!/bin/sh
set -eu

LOG_FILE="${DEPLOY_LOG_FILE:-/tmp/scribe-deploy/deploy.log}"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

if [ "${1:-}" = "-f" ]; then
  tail -n 200 -f "$LOG_FILE"
else
  tail -n 200 "$LOG_FILE"
fi
