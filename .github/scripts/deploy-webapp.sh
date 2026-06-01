#!/usr/bin/env bash
# Deploy a zip package to App Service with retries (handles transient Kudu 502s).
#
# Usage: deploy-webapp.sh <rg> <app> <zip-path> [slot] [max-attempts]
set -euo pipefail

RG="${1:?resource group required}"
APP="${2:?app name required}"
ZIP="${3:?zip path required}"
SLOT="${4:-}"
MAX_ATTEMPTS="${5:-3}"

deploy_args=(-g "$RG" -n "$APP" --src-path "$ZIP" --type zip --timeout 1800000 --enable-kudu-warmup false)
[[ -n "$SLOT" ]] && deploy_args+=(--slot "$SLOT")

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  echo "Deploy attempt ${attempt}/${MAX_ATTEMPTS}..."
  if az webapp deploy "${deploy_args[@]}"; then
    echo "Deploy succeeded"
    exit 0
  fi
  if [[ "$attempt" -lt "$MAX_ATTEMPTS" ]]; then
    echo "Deploy failed; waiting 45s before retry..."
    sleep 45
  fi
done

echo "Deploy failed after ${MAX_ATTEMPTS} attempts" >&2
exit 1
