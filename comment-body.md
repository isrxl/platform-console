<!-- terraform-plan-dashboard -->
## Terraform plan

> 2026-06-01 12:36 UTC · `abc1234` · [workflow run](https://github.com/example/run/1)

| Env | Risk | Add | Chg | Repl | Del | Decision |
|---|---:|---:|---:|---:|---:|---|
| **dev** | 🟡 | 35 | 0 | 0 | 0 | Review carefully |
| **test** | 🟡 | 35 | 0 | 0 | 0 | Review carefully |
| **prod** | 🟡 | 43 | 0 | 0 | 0 | Review carefully |


**Review decision:** ⚠️ **Review resource lists carefully before merging.** Large change set(s).

_Plan-only preview — merge to `main` re-plans and applies via `infra-cd`. Full plan output: download the **tfplan-{env}-abc1234** artifacts from the workflow run._

<details>
<summary>Per-environment details (flags + resource lists)</summary>

<details>
<summary><b>DEV</b> — 🟡 MEDIUM · flags: data · 35 add / 0 destroy</summary>

**Risk flags**

| Flag | Detected |
|---|---|
| Database / storage / Key Vault | ✅ |

**Resources**


**Adding:**
- module.foo.bar
</details>

<details>
<summary><b>TEST</b> — 🟡 MEDIUM · flags: data · 35 add / 0 destroy</summary>

**Risk flags**

| Flag | Detected |
|---|---|
| Database / storage / Key Vault | ✅ |

**Resources**


**Adding:**
- module.foo.bar
</details>

<details>
<summary><b>PROD</b> — 🟡 MEDIUM · flags: data · 43 add / 0 destroy</summary>

**Risk flags**

| Flag | Detected |
|---|---|
| Database / storage / Key Vault | ✅ |

**Resources**


**Adding:**
- module.foo.bar
</details>

</details>
