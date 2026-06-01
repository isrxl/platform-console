#!/usr/bin/env bash
#
# Reads tfplan.json and writes dashboard variables to $GITHUB_OUTPUT.
# Single source of truth for all counts and risk classifications.
set -euo pipefail

PLAN_JSON="tfplan.json"

emit() { printf '%s\n' "$@" >>"$GITHUB_OUTPUT"; }

emit_list() {
  # emit_list <key> <value> — multiline-safe heredoc form for $GITHUB_OUTPUT
  local key="$1" value="$2"
  {
    echo "${key}<<TFPLAN_EOF"
    echo "$value"
    echo "TFPLAN_EOF"
  } >>"$GITHUB_OUTPUT"
}

# ── Failure path ─────────────────────────────────────────────────────────────
# If the plan errored (exit 1) no plan file is produced. Emit a zeroed result so
# the parse step still succeeds and the comment can render the FAILED state
# (driven by PLAN_EXIT_CODE in build-comment.sh).
if [ ! -f "$PLAN_JSON" ]; then
  emit "adds=0" "changes=0" "destroys=0" "replaces=0" "no_ops=0" "total=0" \
    "risk=low" "flag_iam=false" "flag_network=false" "flag_data=false" \
    "flag_destroy=false" "flag_replace=false"
  emit_list "adds_list" ""
  emit_list "changes_list" ""
  emit_list "destroys_list" ""
  emit_list "replaces_list" ""
  exit 0
fi

# ── Action counts from resource_changes[].change.actions ─────────────────────
count_action() {
  jq --arg a "$1" '[.resource_changes[] | select(.change.actions == [$a])] | length' "$PLAN_JSON"
}

ADDS=$(count_action "create")
CHANGES=$(count_action "update")
DESTROYS=$(count_action "delete")

# Replace is a two-element action set. Sorting normalises both orderings:
# destroy-before-create (["delete","create"]) and create-before-destroy.
REPLACES=$(jq '[.resource_changes[] | select((.change.actions | sort) == ["create","delete"])] | length' "$PLAN_JSON")
NO_OPS=$(count_action "no-op")

# ── Total changes (anything that is not no-op) ───────────────────────────────
TOTAL=$((ADDS + CHANGES + DESTROYS + REPLACES))

# ── Risk level ───────────────────────────────────────────────────────────────
RISK="low"
if [ "$DESTROYS" -gt 0 ] || [ "$REPLACES" -gt 0 ]; then
  RISK="critical"
elif [ "$TOTAL" -gt 10 ]; then
  RISK="medium"
fi

# ── Risk flags (detect high-risk resource types) ─────────────────────────────
FLAG_IAM=$(jq '[.resource_changes[] | select(
  .type | test("role_assignment|policy|identity|rbac"; "i")
)] | length > 0' "$PLAN_JSON")

FLAG_NETWORK=$(jq '[.resource_changes[] | select(
  (.type | test("network|firewall|nsg|public_ip|front_door"; "i")) and
  ((.change.after.public_network_access_enabled == true) or
   (.change.after.allow_blob_public_access == true))
)] | length > 0' "$PLAN_JSON")

FLAG_DATA=$(jq '[.resource_changes[] | select(
  .type | test("postgresql|mysql|storage_account|key_vault|cosmos|mssql"; "i")
)] | length > 0' "$PLAN_JSON")

FLAG_DESTROY=$([ "$DESTROYS" -gt 0 ] && echo "true" || echo "false")
FLAG_REPLACE=$([ "$REPLACES" -gt 0 ] && echo "true" || echo "false")

# ── Resource lists for the dashboard ─────────────────────────────────────────
list_resources() {
  jq -r --arg a "$1" \
    '[.resource_changes[] | select(.change.actions == [$a]) | "- " + .address] | join("\n")' \
    "$PLAN_JSON"
}

ADDS_LIST=$(list_resources "create")
CHANGES_LIST=$(list_resources "update")
DESTROYS_LIST=$(list_resources "delete")
REPLACES_LIST=$(jq -r '[.resource_changes[] | select((.change.actions | sort) == ["create","delete"]) | "- " + .address] | join("\n")' "$PLAN_JSON")

# ── Write to GITHUB_OUTPUT ───────────────────────────────────────────────────
emit "adds=$ADDS" "changes=$CHANGES" "destroys=$DESTROYS" "replaces=$REPLACES" \
  "no_ops=$NO_OPS" "total=$TOTAL" "risk=$RISK" \
  "flag_iam=$FLAG_IAM" "flag_network=$FLAG_NETWORK" "flag_data=$FLAG_DATA" \
  "flag_destroy=$FLAG_DESTROY" "flag_replace=$FLAG_REPLACE"
emit_list "adds_list" "$ADDS_LIST"
emit_list "changes_list" "$CHANGES_LIST"
emit_list "destroys_list" "$DESTROYS_LIST"
emit_list "replaces_list" "$REPLACES_LIST"
