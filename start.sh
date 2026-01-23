#!/usr/bin/env sh
set -eu

IMAGE="${IMAGE:-scribe:local}"
NAME="${NAME:-scribe-host}"
ENV_FILE=".env"

docker build -t "$IMAGE" .
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --restart always --env-file "$ENV_FILE" "$IMAGE"
