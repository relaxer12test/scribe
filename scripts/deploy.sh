#!/bin/sh
set -eu

export GIT_TERMINAL_PROMPT=0

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_DIR="${DEPLOY_REPO_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
STATE_DIR="${DEPLOY_STATE_DIR:-/tmp/scribe-deploy}"

COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-scribe}"
export COMPOSE_PROJECT_NAME

LOCK_FILE="${DEPLOY_LOCK_FILE:-$STATE_DIR/lock}"
PENDING_FILE="${DEPLOY_PENDING_FILE:-$STATE_DIR/pending}"
LOG_FILE="${DEPLOY_LOG_FILE:-$STATE_DIR/deploy.log}"
BRANCH="${DEPLOY_BRANCH:-master}"
SERVICES="${DEPLOY_SERVICES:-app postgres caddy}"
RUN_MIGRATIONS="${DEPLOY_RUN_MIGRATIONS:-1}"

log() {
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s %s\n' "$ts" "$*" >> "$LOG_FILE"
  printf '%s %s\n' "$ts" "$*"
}

mkdir -p "$STATE_DIR"

TOKEN="$(cat /proc/sys/kernel/random/uuid)"
tmp="${PENDING_FILE}.tmp.$$"
printf '%s\n' "$TOKEN" > "$tmp"
mv "$tmp" "$PENDING_FILE"

log "Queued deploy request token=$TOKEN. Waiting for lock."
exec 9>"$LOCK_FILE"
flock 9

LATEST_TOKEN="$(cat "$PENDING_FILE")"
if [ "$LATEST_TOKEN" != "$TOKEN" ]; then
  log "Superseded by newer deploy request; exiting."
  exit 0
fi

cd "$REPO_DIR"

log "Fetching origin/$BRANCH."
git fetch origin "$BRANCH"

current="$(git rev-parse HEAD)"
target="$(git rev-parse "origin/$BRANCH")"

if [ "$current" != "$target" ]; then
  log "Deploying $target."
  git checkout "$BRANCH"
  git pull --ff-only origin "$BRANCH"
  docker compose up -d --force-recreate --build $SERVICES
  if [ "$RUN_MIGRATIONS" = "1" ]; then
    log "Running migrations."
    docker compose exec -T app /app/bin/migrate
    log "Migrations complete."
  fi
  log "Deploy finished for $target."
else
  log "Already at $target; no deploy needed."
fi
