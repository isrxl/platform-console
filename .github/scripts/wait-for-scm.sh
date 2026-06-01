#!/usr/bin/env bash
# Poll the SCM (Kudu) site until it responds or the timeout is reached.
#
# Usage: wait-for-scm.sh <app-name> [slot] [max-attempts] [sleep-seconds]
set -euo pipefail

APP_NAME="${1:?app name required}"
SLOT="${2:-}"
MAX_ATTEMPTS="${3:-30}"
SLEEP_SECONDS="${4:-10}"

if [[ -n "$SLOT" ]]; then
  SCM_HOST="${APP_NAME}-${SLOT}"
else
  SCM_HOST="${APP_NAME}"
fi

SCM_URL="https://${SCM_HOST}.scm.azurewebsites.net"
echo "Waiting for SCM at ${SCM_URL} (up to $((MAX_ATTEMPTS * SLEEP_SECONDS))s)..."

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  code="$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 20 "$SCM_URL" || echo "000")"
  echo "SCM probe ${attempt}/${MAX_ATTEMPTS}: HTTP ${code}"

  # 401/403 mean Kudu is up but requires auth; 404 can appear during slot warm-up.
  if [[ "$code" =~ ^(200|401|403|404)$ ]]; then
    echo "SCM is reachable"
    exit 0
  fi

  sleep "$SLEEP_SECONDS"
done

echo "SCM did not become reachable at ${SCM_URL}" >&2
exit 1
