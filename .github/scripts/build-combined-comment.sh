#!/usr/bin/env bash
#
# Reads dashboard-{dev,test,prod}.json fragments and writes one combined PR comment.
# Always-visible: summary table + overall review decision.
# Collapsed per env: flags (YES only), resource lists. Full plan → artifacts only.
set -euo pipefail

FRAG_DIR="${1:-.}"
TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M UTC')
SHORT_SHA="${GITHUB_SHA:0:7}"
RUN_URL="${RUN_URL:-#}"

risk_emoji() {
  local exit_code="$1" risk="$2"
  if [ "$exit_code" = "1" ]; then echo "❌"; return; fi
  if [ "$exit_code" = "0" ]; then echo "✅"; return; fi
  case "$risk" in
    critical) echo "🔴" ;;
    medium)   echo "🟡" ;;
    low)      echo "🟢" ;;
    *)        echo "⚪" ;;
  esac
}

decision_short() {
  local exit_code="$1" risk="$2"
  if [ "$exit_code" = "1" ]; then echo "Plan failed"; return; fi
  if [ "$exit_code" = "0" ]; then echo "No changes"; return; fi
  case "$risk" in
    critical) echo "Block merge" ;;
    medium)   echo "Review carefully" ;;
    low)      echo "Safe to merge" ;;
    *)        echo "Review" ;;
  esac
}

decision_long() {
  local exit_code="$1" risk="$2"
  if [ "$exit_code" = "1" ]; then
    echo "❌ **Plan failed for at least one environment. Do not merge.** Check workflow logs."
    return
  fi
  if [ "$exit_code" = "0" ]; then
    echo "✅ **No infrastructure changes.** Safe to merge."
    return
  fi
  case "$risk" in
    critical) echo "⛔ **Do not merge without senior review.** Destructive changes detected." ;;
    medium)   echo "⚠️ **Review resource lists carefully before merging.** Large change set(s)." ;;
    low)      echo "✅ **Safe to merge.** No destructive or high-risk changes detected." ;;
    *)        echo "⚪ Unable to determine risk level." ;;
  esac
}

# Worst risk across envs: failed(9) > critical(4) > medium(3) > low(2) > no-change(1) > unknown(0)
risk_rank() {
  local exit_code="$1" risk="$2"
  if [ "$exit_code" = "1" ]; then echo 9; return; fi
  if [ "$exit_code" = "0" ]; then echo 1; return; fi
  case "$risk" in
    critical) echo 4 ;;
    medium)   echo 3 ;;
    low)      echo 2 ;;
    *)        echo 0 ;;
  esac
}

flags_yes_only() {
  local f="$1"
  local rows=""
  jq -e '.flag_destroy == true' "$f" >/dev/null 2>&1 && rows+="| Destructive change (destroy) | ✅ |"$'\n'
  jq -e '.flag_replace == true' "$f" >/dev/null 2>&1 && rows+="| Replacement (delete + create) | ✅ |"$'\n'
  jq -e '.flag_iam == true' "$f" >/dev/null 2>&1 && rows+="| IAM / RBAC change | ✅ |"$'\n'
  jq -e '.flag_network == true' "$f" >/dev/null 2>&1 && rows+="| Public network exposure | ✅ |"$'\n'
  jq -e '.flag_data == true' "$f" >/dev/null 2>&1 && rows+="| Database / storage / Key Vault | ✅ |"$'\n'
  if [ -z "$rows" ]; then
    echo "_No risk flags triggered._"
  else
    printf '| Flag | Detected |\n|---|---|\n%s' "$rows"
  fi
}

resource_body() {
  local f="$1"
  local body=""
  local adds changes destroys replaces
  adds=$(jq -r '.adds_list // ""' "$f")
  changes=$(jq -r '.changes_list // ""' "$f")
  destroys=$(jq -r '.destroys_list // ""' "$f")
  replaces=$(jq -r '.replaces_list // ""' "$f")
  [ -n "$adds" ]     && body+=$'\n**Adding:**\n'"$adds"$'\n'
  [ -n "$changes" ]  && body+=$'\n**Updating:**\n'"$changes"$'\n'
  [ -n "$replaces" ] && body+=$'\n**Replacing (destroy + create):**\n'"$replaces"$' ⚠️\n'
  [ -n "$destroys" ] && body+=$'\n**Destroying:**\n'"$destroys"$' ⚠️\n'
  [ -z "$body" ] && body="_No resources changing._"
  printf '%s' "$body"
}

flag_summary() {
  local f="$1"
  local parts=()
  jq -e '.flag_destroy == true' "$f" >/dev/null 2>&1 && parts+=("destroy")
  jq -e '.flag_replace == true' "$f" >/dev/null 2>&1 && parts+=("replace")
  jq -e '.flag_iam == true' "$f" >/dev/null 2>&1 && parts+=("iam")
  jq -e '.flag_network == true' "$f" >/dev/null 2>&1 && parts+=("network")
  jq -e '.flag_data == true' "$f" >/dev/null 2>&1 && parts+=("data")
  if [ ${#parts[@]} -eq 0 ]; then
    echo "none"
  else
    local IFS=', '
    echo "${parts[*]}"
  fi
}

# ── Summary table + track worst risk ─────────────────────────────────────────
TABLE="| Env | Risk | Add | Chg | Repl | Del | Decision |
|---|---:|---:|---:|---:|---:|---|
"
DETAILS=""
WORST_RANK=0
WORST_EXIT="2"
WORST_RISK="low"

for ENV in dev test prod; do
  F="${FRAG_DIR}/dashboard-${ENV}.json"
  if [ ! -f "$F" ]; then
    TABLE+="| **${ENV}** | ⚠️ | — | — | — | — | Plan did not run |
"
    WORST_RANK=9
    WORST_EXIT="1"
    continue
  fi

  EXIT=$(jq -r '.plan_exit_code' "$F")
  RISK=$(jq -r '.risk' "$F")
  ADDS=$(jq -r '.adds' "$F")
  CHANGES=$(jq -r '.changes' "$F")
  REPLACES=$(jq -r '.replaces' "$F")
  DESTROYS=$(jq -r '.destroys' "$F")
  EMOJI=$(risk_emoji "$EXIT" "$RISK")
  SHORT=$(decision_short "$EXIT" "$RISK")
  RANK=$(risk_rank "$EXIT" "$RISK")

  TABLE+="| **${ENV}** | ${EMOJI} | ${ADDS} | ${CHANGES} | ${REPLACES} | ${DESTROYS} | ${SHORT} |
"

  if [ "$RANK" -gt "$WORST_RANK" ]; then
    WORST_RANK=$RANK
    WORST_EXIT=$EXIT
    WORST_RISK=$RISK
  fi

  ENV_UPPER="${ENV^^}"
  RISK_UPPER="${RISK^^}"
  FLAGS=$(flag_summary "$F")
  DETAILS+=$'\n<details>\n<summary><b>'"${ENV_UPPER}"$'</b> — '"${EMOJI} ${RISK_UPPER}"$' · flags: '"${FLAGS}"$' · '"${ADDS}"$' add / '"${DESTROYS}"$' destroy</summary>\n\n'
  DETAILS+=$'**Risk flags**\n\n'
  DETAILS+=$(flags_yes_only "$F")
  DETAILS+=$'\n\n**Resources**\n\n'
  DETAILS+=$(resource_body "$F")
  DETAILS+=$'\n</details>\n'
done

OVERALL=$(decision_long "$WORST_EXIT" "$WORST_RISK")

cat >comment-body.md <<COMMENT
<!-- terraform-plan-dashboard -->
## Terraform plan

> ${TIMESTAMP} · \`${SHORT_SHA}\` · [workflow run](${RUN_URL})

${TABLE}

**Review decision:** ${OVERALL}

_Plan-only preview — merge to \`main\` re-plans and applies via \`infra-cd\`. Full plan output: download the **tfplan-{env}-${SHORT_SHA}** artifacts from the workflow run._

<details>
<summary>Per-environment details (flags + resource lists)</summary>
${DETAILS}
</details>
COMMENT
