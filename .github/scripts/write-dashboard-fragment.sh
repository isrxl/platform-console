#!/usr/bin/env bash
#
# Serialises parse-plan.sh outputs into dashboard-{env}.json for the combine step.
set -euo pipefail

ENV="${ENVIRONMENT:?ENVIRONMENT required}"

jq -n \
  --arg environment "$ENV" \
  --arg plan_exit_code "${PLAN_EXIT_CODE:-1}" \
  --argjson adds "${ADDS:-0}" \
  --argjson changes "${CHANGES:-0}" \
  --argjson destroys "${DESTROYS:-0}" \
  --argjson replaces "${REPLACES:-0}" \
  --argjson no_ops "${NO_OPS:-0}" \
  --argjson total "${TOTAL:-0}" \
  --arg risk "${RISK:-low}" \
  --argjson flag_iam "${FLAG_IAM:-false}" \
  --argjson flag_network "${FLAG_NETWORK:-false}" \
  --argjson flag_data "${FLAG_DATA:-false}" \
  --argjson flag_destroy "${FLAG_DESTROY:-false}" \
  --argjson flag_replace "${FLAG_REPLACE:-false}" \
  --arg adds_list "${ADDS_LIST:-}" \
  --arg changes_list "${CHANGES_LIST:-}" \
  --arg destroys_list "${DESTROYS_LIST:-}" \
  --arg replaces_list "${REPLACES_LIST:-}" \
  '{
    environment: $environment,
    plan_exit_code: $plan_exit_code,
    adds: $adds,
    changes: $changes,
    destroys: $destroys,
    replaces: $replaces,
    no_ops: $no_ops,
    total: $total,
    risk: $risk,
    flag_iam: $flag_iam,
    flag_network: $flag_network,
    flag_data: $flag_data,
    flag_destroy: $flag_destroy,
    flag_replace: $flag_replace,
    adds_list: $adds_list,
    changes_list: $changes_list,
    destroys_list: $destroys_list,
    replaces_list: $replaces_list
  }' >"dashboard-${ENV}.json"
