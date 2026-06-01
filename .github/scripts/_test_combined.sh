#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/dashboard-dev.json" <<'JSON'
{"environment":"dev","plan_exit_code":"2","adds":35,"changes":0,"destroys":0,"replaces":0,"no_ops":0,"total":35,"risk":"medium","flag_iam":false,"flag_network":false,"flag_data":true,"flag_destroy":false,"flag_replace":false,"adds_list":"- module.foo.bar","changes_list":"","destroys_list":"","replaces_list":""}
JSON
cp "$TMP/dashboard-dev.json" "$TMP/dashboard-test.json"
jq '.environment="test"' "$TMP/dashboard-test.json" >"$TMP/t.json" && mv "$TMP/t.json" "$TMP/dashboard-test.json"
jq '.environment="prod" | .adds=43 | .total=43' "$TMP/dashboard-dev.json" >"$TMP/dashboard-prod.json"

export GITHUB_SHA=abc1234def RUN_URL=https://github.com/example/run/1
bash "$HERE/build-combined-comment.sh" "$TMP" >"$TMP/out.md"
grep -E "Terraform plan|dev|prod|Review decision|Per-environment" "$TMP/out.md"
echo "OK: combined comment built"
