#!/usr/bin/env bash
# Open or close a temporary App Service access window for GitHub-hosted runner deploys.
#
# Usage:
#   app-deploy-window.sh open  <rg> <app> <runner-ip> [slot]
#   app-deploy-window.sh close <rg> <app> <main-pna> [slot] [slot-pna]
#
# When [slot] is set, rules are applied to both the slot (SCM + main) and production
# (main + SCM). Production SCM is included because slot deploys still touch the
# parent site's deployment API in some paths.
set -euo pipefail

RULE_MAIN="gh-runner"
RULE_SCM="gh-runner-scm"

remove_rules() {
  local rg="$1" app="$2" slot="${3:-}"
  local slot_args=()
  [[ -n "$slot" ]] && slot_args=(--slot "$slot")

  az webapp config access-restriction remove -g "$rg" -n "$app" "${slot_args[@]}" \
    --rule-name "$RULE_MAIN" -o none 2>/dev/null || true
  az webapp config access-restriction remove -g "$rg" -n "$app" "${slot_args[@]}" \
    --scm-site true --rule-name "$RULE_SCM" -o none 2>/dev/null || true
}

add_rules() {
  local rg="$1" app="$2" ip_cidr="$3" slot="${4:-}"
  local slot_args=()
  [[ -n "$slot" ]] && slot_args=(--slot "$slot")

  az webapp config access-restriction add -g "$rg" -n "$app" "${slot_args[@]}" \
    --rule-name "$RULE_MAIN" --action Allow --ip-address "$ip_cidr" --priority 100 -o none
  az webapp config access-restriction add -g "$rg" -n "$app" "${slot_args[@]}" \
    --scm-site true --rule-name "$RULE_SCM" --action Allow --ip-address "$ip_cidr" --priority 100 -o none
}

open_window() {
  local rg="$1" app="$2" ip="$3" slot="${4:-}"
  local ip_cidr="${ip}/32"

  echo "Opening deploy window for ${app}${slot:+ (slot ${slot})} from ${ip_cidr}"

  if [[ -n "$slot" ]]; then
    remove_rules "$rg" "$app" "$slot"
  fi
  remove_rules "$rg" "$app"

  if [[ -n "$slot" ]]; then
    az webapp update -g "$rg" -n "$app" --slot "$slot" --set publicNetworkAccess=Enabled -o none
  fi
  az webapp update -g "$rg" -n "$app" --set publicNetworkAccess=Enabled -o none

  if [[ -n "$slot" ]]; then
    add_rules "$rg" "$app" "$ip_cidr" "$slot"
  fi
  add_rules "$rg" "$app" "$ip_cidr"
}

close_window() {
  local rg="$1" app="$2" main_pna="$3" slot="${4:-}" slot_pna="${5:-}"

  echo "Closing deploy window for ${app}${slot:+ (slot ${slot})}"

  if [[ -n "$slot" ]]; then
    remove_rules "$rg" "$app" "$slot"
    az webapp update -g "$rg" -n "$app" --slot "$slot" \
      --set "publicNetworkAccess=${slot_pna:-Disabled}" -o none || true
  fi

  remove_rules "$rg" "$app"
  az webapp update -g "$rg" -n "$app" \
    --set "publicNetworkAccess=${main_pna:-Disabled}" -o none || true
}

case "${1:-}" in
  open)
    [[ $# -ge 4 ]] || { echo "Usage: $0 open <rg> <app> <runner-ip> [slot]" >&2; exit 1; }
    open_window "$2" "$3" "$4" "${5:-}"
    ;;
  close)
    [[ $# -ge 4 ]] || { echo "Usage: $0 close <rg> <app> <main-pna> [slot] [slot-pna]" >&2; exit 2; }
    close_window "$2" "$3" "$4" "${5:-}" "${6:-}"
    ;;
  *)
    echo "Usage: $0 open|close ..." >&2
    exit 1
    ;;
esac
