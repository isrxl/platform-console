#!/usr/bin/env bash
#
# Assembles the PR dashboard comment from parse-plan.sh outputs (passed as env
# vars) and writes it to comment-body.md. The github-script step reads that file.
set -euo pipefail

ENV_UPPER="${ENVIRONMENT^^}"
TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M UTC')
SHORT_SHA="${GITHUB_SHA:0:7}"

# ── Risk label ───────────────────────────────────────────────────────────────
case "$RISK" in
  critical) RISK_LABEL="🔴 CRITICAL — Destructive changes detected" ;;
  medium)   RISK_LABEL="🟡 MEDIUM — Large change set, review carefully" ;;
  low)      RISK_LABEL="🟢 LOW — No destructive or high-risk changes" ;;
  *)        RISK_LABEL="⚪ UNKNOWN" ;;
esac

if [ "$PLAN_EXIT_CODE" = "1" ]; then
  RISK_LABEL="❌ PLAN FAILED — Check workflow logs"
fi

if [ "$PLAN_EXIT_CODE" = "0" ]; then
  RISK_LABEL="✅ NO CHANGES — Infrastructure is up-to-date"
fi

# ── Review decision ──────────────────────────────────────────────────────────
case "$RISK" in
  critical) DECISION="⛔ **Do not merge without senior review.** Destructive changes detected." ;;
  medium)   DECISION="⚠️ **Review resource list carefully before merging.** Large change set." ;;
  low)      DECISION="✅ **Safe to merge.** No destructive or high-risk changes detected." ;;
  *)        DECISION="⚪ Unable to determine risk level." ;;
esac

if [ "$PLAN_EXIT_CODE" = "1" ]; then
  DECISION="❌ **Plan failed. Do not merge.** Check workflow logs for errors."
fi

if [ "$PLAN_EXIT_CODE" = "0" ]; then
  DECISION="✅ **No infrastructure changes.** Safe to merge."
fi

# ── Risk flags table ─────────────────────────────────────────────────────────
yn() { [ "$1" = "true" ] && echo "✅ YES" || echo "❌ No"; }

FLAGS_TABLE="| Flag | Detected |
|---|---|
| Destructive change (destroy) | $(yn "$FLAG_DESTROY") |
| Replacement (delete + create) | $(yn "$FLAG_REPLACE") |
| IAM / RBAC change | $(yn "$FLAG_IAM") |
| Public network exposure | $(yn "$FLAG_NETWORK") |
| Database / storage / Key Vault | $(yn "$FLAG_DATA") |"

# ── Resource sections (only render non-empty sections) ───────────────────────
RESOURCE_BODY=""
[ -n "$ADDS_LIST" ]     && RESOURCE_BODY+=$'\n**Adding:**\n'"$ADDS_LIST"$'\n'
[ -n "$CHANGES_LIST" ]  && RESOURCE_BODY+=$'\n**Updating:**\n'"$CHANGES_LIST"$'\n'
[ -n "$REPLACES_LIST" ] && RESOURCE_BODY+=$'\n**Replacing (destroy + create):**\n'"$REPLACES_LIST"$' ⚠️\n'
[ -n "$DESTROYS_LIST" ] && RESOURCE_BODY+=$'\n**Destroying:**\n'"$DESTROYS_LIST"$' ⚠️\n'
[ -z "$RESOURCE_BODY" ] && RESOURCE_BODY="_No resources changing._"

# ── Full plan output ─────────────────────────────────────────────────────────
# A GitHub issue comment is capped at 65536 chars. Guard against a large plan
# breaching that (which would make the API call fail and post nothing).
PLAN_OUTPUT=$(cat plan-output.txt 2>/dev/null || echo "(plan output unavailable)")
MAX=45000
if [ "${#PLAN_OUTPUT}" -gt "$MAX" ]; then
  PLAN_OUTPUT="${PLAN_OUTPUT:0:$MAX}

... truncated — download the plan-output.txt artifact for the full output ..."
fi

# ── Assemble comment ─────────────────────────────────────────────────────────
cat >comment-body.md <<COMMENT
<!-- terraform-plan-dashboard-${ENV_UPPER} -->
## Terraform Plan — ${ENV_UPPER}

> Last updated: ${TIMESTAMP} | Commit: \`${SHORT_SHA}\`

---

### Status
**Risk Level:** ${RISK_LABEL}

| Action | Count |
|---|---:|
| Add | ${ADDS} |
| Change | ${CHANGES} |
| Replace | ${REPLACES} |
| Destroy | ${DESTROYS} |
| No-op | ${NO_OPS} |

---

### 🚨 Risk Flags

${FLAGS_TABLE}

---

### Review Decision

${DECISION}

---

<details>
<summary>📋 Resources Changing (${ADDS} add / ${CHANGES} change / ${REPLACES} replace / ${DESTROYS} destroy)</summary>

${RESOURCE_BODY}
</details>

<details>
<summary>📄 Full Terraform Plan Output</summary>

\`\`\`
${PLAN_OUTPUT}
\`\`\`

</details>
COMMENT
