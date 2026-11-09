#!/bin/sh
# Runs the server as PUID:PGID when set (NAS-style), otherwise as root.
set -e
mkdir -p "$DATA_PATH"
if [ -n "$PUID" ] && [ "$PUID" != "0" ]; then
  PGID="${PGID:-$PUID}"
  chown -R "$PUID:$PGID" "$DATA_PATH" 2>/dev/null || true
  exec setpriv --reuid="$PUID" --regid="$PGID" --clear-groups \
    uvicorn app.main:app --host 0.0.0.0 --port "$PORT" --no-access-log --proxy-headers --forwarded-allow-ips "*"
fi
exec uvicorn app.main:app --host 0.0.0.0 --port "$PORT" --no-access-log --proxy-headers --forwarded-allow-ips "*"
