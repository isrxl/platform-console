# Platform Console

A secure internal web application on Azure that demonstrates a production-grade
private-networking reference architecture: **Managed Identity**, **private
endpoints** for every backend service, a fully **private App Service**, and
**GitOps** delivery via two independent GitHub Actions pipelines.

> Dual purpose: a hands-on reference for the Inlogik Senior Cloud Engineer
> technical submission, and a public Cloudville showcase of Azure private
> networking + Managed Identity + GitOps.

---

## What it is

Platform Console is a Flask app that engineering teams use to manage and monitor
their platform. Each of its five sections deliberately exercises a different
Azure pattern, so the running app is also a live proof of the architecture.

| Section | What it does | Azure pattern proven |
|---|---|---|
| Platform Health | Live status of all dependencies (30s refresh) | Managed Identity → Key Vault, SQL over private endpoint |
| Feature Flags | Toggle flags per environment, audited to SQL | SQL write over private endpoint |
| Deployment History | Every deploy recorded by Git SHA + semver | Pipeline → app → SQL injection |
| Secret Expiry Monitor | Colour-coded Key Vault secret expiry | Managed Identity → Key Vault list/properties API |
| Release Notes | Publish release notes per version | SQL read/write over private endpoint |

---

## Architecture overview

```
                 GitHub Actions (infra + app pipelines)
                              │  (control plane via Service Principal)
                              ▼
   ┌───────────────────────── VNet (10.x.0.0/16) ─────────────────────────┐
   │                                                                       │
   │  snet-app (delegated)        snet-inbound            snet-pe          │
   │  ┌───────────────┐           ┌──────────────┐        ┌─────────────┐  │
   │  │ App Service   │◀── VNet ──│ App inbound  │        │ KV  PE      │  │
   │  │ (P0v4, Linux) │  integ.   │ private EP   │        │ SQL PE      │  │
   │  │ public: OFF   │──────────────────────────────────▶│             │  │
   │  └──────┬────────┘   private endpoints + private DNS  └─────┬───────┘  │
   │         │ Managed Identity                                  │          │
   │         ▼                                                   ▼          │
   │   Key Vault (RBAC)  ◀──── db-connection-string ────  Azure SQL (Basic) │
   │                                                                       │
   │  snet-jump (prod only): Windows jump VM + Bastion Developer (validate)│
   └───────────────────────────────────────────────────────────────────────┘
```

- **App Service public endpoint is disabled.** Ingress is via a private endpoint
  in `snet-inbound`; outbound is via regional VNet integration in `snet-app`.
- **Key Vault and SQL are private-endpoint only**, resolved through three private
  DNS zones linked to the VNet.
- **No credentials in code.** The app authenticates to Key Vault with a
  user-assigned Managed Identity (`Key Vault Secrets User`) and reads the SQL
  connection string from a secret.

### Azure services used

| Service | Purpose | Why chosen |
|---|---|---|
| App Service Premium v4 (P0v4) | Hosts the Flask app | Private endpoint support, ~17% cheaper than P0v3, Linux (no Windows licensing) |
| Azure SQL Database (Basic) | App data | Cheapest tier sufficient for the lab; private-endpoint only |
| Key Vault (RBAC) | Secret storage | Managed Identity access, no secrets in code |
| Private Endpoints ×3 | App / KV / SQL ingress | Keeps all backend traffic off the public internet |
| Private DNS Zones ×3 | Name resolution | Maps service hostnames to private IPs inside the VNet |
| User-assigned Managed Identity | App → Key Vault auth | Lets Terraform grant RBAC before the app exists |
| Log Analytics + App Insights | Telemetry & logs | Centralised observability; metric alerts via Azure Monitor |
| Jump VM + Bastion (Developer) | Prod validation | Browse the private app from inside the VNet, then destroy |

### Private access patterns

Three private endpoints, each paired with a private DNS zone linked to the VNet:

| Private DNS zone | Resolves |
|---|---|
| `privatelink.azurewebsites.net` | App Service hostname → private IP in `snet-inbound` |
| `privatelink.vaultcore.azure.net` | Key Vault hostname → private IP in `snet-pe` |
| `privatelink.database.windows.net` | SQL Server hostname → private IP in `snet-pe` |

---

## Repository layout

```
platform-console/
├── .github/
│   ├── actions/tf-apply/          # Composite action: init + plan + apply
│   ├── scripts/                   # parse-plan.sh + build-comment.sh (PR plan dashboard)
│   └── workflows/                 # app-ci/cd, infra-ci/cd, infra-drift, terraform-plan-dashboard
├── modules/
│   ├── networking/                # VNet, subnets, NSGs, private DNS zones
│   ├── database/                  # SQL Server + DB + SQL private endpoint
│   ├── security/                  # Key Vault, Managed Identity, RBAC, KV PE, secrets
│   ├── compute/                   # App Service, slot, VNet integ, app PE, jump VM/Bastion
│   └── monitoring/                # Log Analytics, App Insights, action group
├── app/                           # Flask application
│   ├── app.py  config.py  db.py  keyvault.py
│   ├── templates/index.html       # Single-page UI (Tailwind via CDN)
│   ├── sql/schema.sql
│   └── tests/
├── main.tf  variables.tf  outputs.tf  versions.tf  backend.tf
└── dev.tfvars  test.tfvars  prod.tfvars
```

---

## Terraform design

- **Single root** `main.tf` calls all five modules — no per-environment directories.
- **Environment differences live only in `.tfvars`** (CIDRs + `deploy_jump_vm`).
- **State is isolated per environment** via a backend `key` injected by the
  pipeline at init time (`dev/`, `test/`, `prod/`).
- **Modules are environment-agnostic** — no environment branching inside them.

### A note on the dedicated `database` module

The handoff originally folded SQL into the networking/security modules. This
implementation uses a **dedicated `database` module** that owns the SQL Server,
the database, and the SQL private endpoint, and exports the connection string.
The `security` module consumes that output to seed the `db-connection-string`
Key Vault secret. This keeps SQL concerns in one place and the dependency graph
linear: `networking → database → security → compute`.

### Security scanning (tfsec + checkov)

`infra-ci` runs **tfsec** and **checkov** as hard gates. A small set of checkov
checks is skipped (see `skip_check` in `infra-ci.yml`) — each is a conscious
trade-off for this single-region, cost-constrained lab, not an oversight:

| Category | Checks | Rationale |
|---|---|---|
| HA / zone redundancy / failover | `CKV_AZURE_212/225/229` | Single-region lab; multi-AZ adds cost |
| Teardown-friendly Key Vault | `CKV_AZURE_42/110` | Purge protection blocks clean lab teardown |
| SQL auth (not Entra-only) | `CKV2_AZURE_27` | Documented design choice; credential lives only in Key Vault |
| SQL auditing / VA | `CKV_AZURE_23/24`, `CKV2_AZURE_2` | Require extra storage; out of lab scope |
| Ephemeral jump VM | `CKV_AZURE_50/151` | Created only for validation, then destroyed |
| Not applicable to a private, code-deployed app | `CKV_AZURE_13/17/88/224` | Easy Auth / client certs / Azure Files / Ledger unused |

Findings that were cheap and correct to fix (Key Vault secret **expiry** and
**content-type**) are addressed in code rather than skipped.

### Naming convention

Resources follow `{type}-{project}-webapp-{env}-{loc}` (e.g.
`rg-cdvlplatcon-webapp-prod-aue`). The `project` token is a variable
(`cdvlplatcon` for this deployment) set per environment in the `.tfvars` files;
leaving it empty falls back to `{type}-webapp-{env}-{loc}`. Two exceptions are
driven by Azure name-length limits:

- **Key Vault** (max 24 chars) drops the `webapp` token → `kv-{project}-{env}-{loc}`
  (e.g. `kv-cdvlplatcon-prod-aue`, 23 chars).
- **Jump VM** sets an explicit 15-char-safe `computer_name` (`jump-{env}`)
  separate from its longer Azure resource name (Windows hostname limit).

Sub-resources that never carried `webapp` (subnets, NSGs, private endpoints, DNS
links) use `{type}-{project}-{env}-{loc}`.

### Reconciled design decisions

| Topic | Handoff text | Implemented as | Why |
|---|---|---|---|
| App identity | "system-assigned" (§2.3) | **User-assigned** `id-{project}-webapp-*` | Matches the naming table and lets Terraform grant KV RBAC before the app exists |
| Key Vault network | "public access disabled" | Public access **on**, firewall **default-deny** + private endpoint + pipeline-IP allow | GitOps secret-seeding needs data-plane reach; the app still uses the private endpoint |
| SQL ownership | networking/security | **dedicated `database` module** | Per request; cleaner boundaries |
| Resource naming | `{type}-webapp-{env}-aue` | `{type}-{project}-webapp-{env}-aue` | Adds an org/project token; KV + jump VM special-cased for length limits |
| Resource group | Terraform-created | **Pre-created, referenced via `data` source** | RGs are provisioned out-of-band; the pipeline SP holds RBAC-admin scoped per-RG. All planned environments' RGs must exist before `infra-ci` runs |

---

## CI/CD design

Two independent pipelines. **The pipeline is the only path to production** — no
operator runs Terraform directly, and promotion is gated by automated tests, not
human approval.

| Workflow | Trigger | Does |
|---|---|---|
| `infra-ci` | PR touching `*.tf`/`*.tfvars` | fmt, validate, tfsec, checkov (static quality gate — no Azure access) |
| `terraform-plan-dashboard` | PR to `main` touching `*.tf`/`*.tfvars` | `plan` matrix for dev/test/prod; posts a per-env risk dashboard comment + uploads `tfplan.json` artifacts |
| `infra-cd` | merge to `main` (infra paths) | `apply` per environment, gated by `DEPLOY_DEV/TEST/PROD` env toggles |
| `infra-drift` | nightly 6am AEST + manual | `plan -detailed-exitcode` matrix; exit code 2 raises a GitHub Issue |
| `app-ci` | PR touching `app/**` | flake8, pytest, pip-audit, build validation |
| `app-cd` | merge to `main` (app paths) + weekly | deploy dev→test→prod, prod via staging-slot swap with auto-rollback |

Versioning: `APP_VERSION` (Git SHA), `SEMANTIC_VERSION` (latest tag), and
`DEPLOYED_AT` are injected as app settings at deploy time; the pipeline records
each deploy via `POST /api/deployments`.

---

## Prerequisites

- Azure subscription + `az` CLI
- Terraform ≥ 1.6
- Python 3.11 (for local app work)
- A GitHub repository with the secrets/environments below

---

## Deployment guide

### 1. Bootstrap Terraform state + resource groups (once, manually)

```bash
# 1a. State storage
az group create --name rg-tfstate --location australiaeast

az storage account create \
  --name sttfstate$RANDOM \
  --resource-group rg-tfstate \
  --sku Standard_LRS \
  --min-tls-version TLS1_2

az storage container create --name tfstate --account-name <storage-account>

# 1b. Application resource groups are pre-created out-of-band — Terraform
#     references them via a data source (modules/networking), it does NOT
#     create them. Create one per environment you intend to plan/apply.
#     NOTE: the plan dashboard plans dev/test/prod on every PR, so ALL THREE
#     must exist or the data-source read fails during plan.
for ENV in dev test prod; do
  az group create --name "rg-cdvlplatcon-webapp-${ENV}-aue" --location australiaeast
done
```

### 2. Create the pipeline service principal and assign roles

```bash
SUBSCRIPTION_ID="<your-subscription-id>"
SP_NAME="sp-platform-console-pipeline"
STATE_RG="rg-tfstate"
STATE_SA="cdvlplatcone46dcefeb780"

# 2a. Create the SP with Contributor at subscription scope.
#     No client secret is needed — the pipeline authenticates via OIDC (step 2e).
az ad sp create-for-rbac \
  --name "$SP_NAME" \
  --role Contributor \
  --scopes "/subscriptions/$SUBSCRIPTION_ID"

# 2b. Capture the SP's app (client) id and object id for the grants below.
APP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv)
SP_OBJECT_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].id" -o tsv)

# 2c. State backend uses Azure AD auth -> needs data-plane access to blobs.
STATE_SA_ID=$(az storage account show -g "$STATE_RG" -n "$STATE_SA" --query id -o tsv)
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$STATE_SA_ID"

# 2d. The security module creates RBAC role assignments (Key Vault Secrets User
#     for the app identity + Key Vault Administrator for the deployer). Contributor
#     CANNOT write role assignments. Grant Role Based Access Control Administrator
#     scoped to each pre-created RG (least privilege — no subscription-wide grant).
for ENV in dev test prod; do
  RG_ID=$(az group show -n "rg-cdvlplatcon-webapp-${ENV}-aue" --query id -o tsv)
  az role assignment create \
    --assignee-object-id "$SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Role Based Access Control Administrator" \
    --scope "$RG_ID"
done

# 2e. Federate GitHub OIDC -> this SP (passwordless). One credential per subject
#     the workflows present: PR (infra-ci), default branch (infra-drift), and
#     each environment (infra-cd / app-cd jobs that set `environment:`).
REPO="isrxl/platform-console"
declare -A SUBJECTS=(
  [gh-pull-request]="repo:${REPO}:pull_request"
  [gh-main]="repo:${REPO}:ref:refs/heads/main"
  [gh-env-dev]="repo:${REPO}:environment:dev"
  [gh-env-test]="repo:${REPO}:environment:test"
  [gh-env-prod]="repo:${REPO}:environment:prod"
)
for NAME in "${!SUBJECTS[@]}"; do
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\":\"${NAME}\",
    \"issuer\":\"https://token.actions.githubusercontent.com\",
    \"subject\":\"${SUBJECTS[$NAME]}\",
    \"audiences\":[\"api://AzureADTokenExchange\"]
  }"
done
```

> Scoping the RBAC-admin grant to each resource group (rather than
> `User Access Administrator` at subscription scope) keeps the pipeline's
> privilege to assign roles confined to exactly the resource groups it manages.

### 3. Add GitHub variables + secrets

Authentication is **OIDC (federated workload identity)** — there is no stored
client secret. The Azure identifiers are non-sensitive **Actions variables**;
only the state-backend config is kept as secrets.

```bash
# OIDC identifiers (Actions *variables*, not secrets)
gh variable set AZURE_CLIENT_ID --body "$APP_ID"
gh variable set AZURE_TENANT_ID --body "$(az account show --query tenantId -o tsv)"
gh variable set AZURE_SUBSCRIPTION_ID --body "$(az account show --query id -o tsv)"

# State backend config (secrets)
gh secret set TF_STATE_RG --body "rg-tfstate"
gh secret set TF_STATE_SA --body "cdvlplatcone46dcefeb780"
gh secret set TF_STATE_CONTAINER --body "tfstate"
```

| Name | Kind | Value |
|---|---|---|
| `AZURE_CLIENT_ID` | variable | SP application (client) ID |
| `AZURE_TENANT_ID` | variable | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | variable | Azure subscription ID |
| `TF_STATE_RG` | secret | `rg-tfstate` |
| `TF_STATE_SA` | secret | `cdvlplatcone46dcefeb780` |
| `TF_STATE_CONTAINER` | secret | `tfstate` |

> **How it works:** workflows declare `permissions: id-token: write`, then
> `azure/login@v2` exchanges the GitHub OIDC token for an Azure token. Terraform
> uses the same token via `ARM_USE_OIDC=true` + `ARM_CLIENT_ID/TENANT_ID/SUBSCRIPTION_ID`.
> No long-lived credential is ever stored in GitHub.

### 4. Create GitHub Environments

`dev`, `test`, `prod` — **no protection rules** (quality is gated by tests in the
pipeline, not by manual approval).

### 5. Deploy

Push to `main`. `infra-cd` runs with `DEPLOY_PROD=true` and provisions prod
end-to-end. Then push app changes (or run `app-cd` manually) to deploy the Flask
app. To deploy dev/test as well, flip `DEPLOY_DEV`/`DEPLOY_TEST` to `'true'` in
`infra-cd.yml`.

> **Private-network deployment caveat:** because the App Service public endpoint
> is disabled, `app-cd`'s deploy and smoke-test steps cannot reach the app from a
> GitHub-hosted runner. For a true private deploy, run `app-cd` on a **self-hosted
> runner inside the VNet** (set `runs-on`) or open a temporary SCM IP-allow
> window. The infra pipeline is unaffected (it uses the Azure control plane).

---

## Validation guide (prod, via jump VM)

`prod.tfvars` sets `deploy_jump_vm = true`. RDP to the Windows jump VM through
Azure Bastion, then from inside the VNet:

1. Open Edge → `https://app-cdvlplatcon-webapp-prod-aue.azurewebsites.net` (confirms private ingress)
2. **Platform Health** — all green (App Service, SQL, Key Vault, App Insights)
3. **Feature Flags** — table loads; toggle a flag (confirms SQL write over PE)
4. **Secret Expiry Monitor** — secrets listed (confirms MI → Key Vault)
5. **Deployment History** — pipeline records visible
6. **Release Notes** — create one (confirms SQL write)
7. `/health` returns JSON with status + version
8. Change a resource in the Portal → `infra-drift` raises a GitHub Issue
9. Destroy the jump VM (below)

Retrieve jump VM credentials:

```bash
terraform output -raw jump_vm_admin_password
```

---

## Teardown

Destroy the jump VM after validation (keep the rest running):

```bash
terraform destroy \
  -target 'module.compute.azurerm_windows_virtual_machine.jump[0]' \
  -target 'module.compute.azurerm_bastion_host.jump[0]' \
  -target 'module.compute.azurerm_network_interface.jump[0]' \
  -var-file=prod.tfvars
```

Destroy everything:

```bash
terraform destroy -var-file=prod.tfvars
```

This destroys all resources *inside* the resource group but leaves the resource
group itself (it is referenced via a data source, not managed by Terraform).
Delete it manually if desired: `az group delete -n rg-cdvlplatcon-webapp-prod-aue`.
The bootstrap state storage account is separate and can remain (~$0.05/month).

---

## Cost estimate (prod, ~2 days)

| Component | 2-day (AUD) |
|---|---|
| App Service P0v4 | ~$10.00 |
| Azure SQL (Basic) | ~$0.54 |
| Private endpoints ×3 | ~$3.09 |
| Key Vault | ~$0.08 |
| State storage | ~$0.08 |
| Jump VM (B2s, ~2h) | ~$0.12 |
| Log Analytics / App Insights / Bastion Developer | free at lab scale |
| **Total** | **~$13.91 AUD** |

---

## App Service tier selection

**P0v4** is chosen for private-endpoint support, lower cost than P0v3, and higher
throughput. If the `azurerm` provider does not yet recognise the `P0v4`
`sku_name`, fall back by setting `app_service_sku = "P0v3"` in the `.tfvars`
files — the architecture is otherwise identical.

---

## Known limitations

- **Dynamic outbound IP on P0v4** — not relevant here; all backend traffic uses
  private endpoints.
- **Single region** — no multi-region/DR. Future enhancement.
- **SQL auth (not Entra-only)** — connection string lives in Key Vault and is
  fetched via Managed Identity, so no credential is in code.
- **No WAF** — the app's public endpoint is disabled (private only); Front Door /
  App Gateway WAF is a future enhancement.
- **Jump VM lifecycle** — must be manually destroyed after validation.

---

## Future enhancements

Deferred work, captured so it isn't lost:

- **Self-hosted, VNet-integrated CI runner.** `app-cd` currently reaches the
  private App Service by briefly opening a runner-IP-only public-access window,
  then re-locking. A self-hosted runner placed inside (or peered to) the VNet
  would remove that window entirely and deploy straight over private endpoints.
  **Not free:** GitHub charges nothing for self-hosted runners, but you pay for
  the Azure compute that hosts them — e.g. a small always-on VM (~A$15–60/mo
  depending on size) or a scale-to-zero option (Container Apps / ACI jobs) to
  avoid idle cost. Trade-off: standing infrastructure + patching vs. the current
  zero-cost, zero-standing-footprint IP window.
- **Infracost in `infra-ci`.** Add a cost-diff step to the PR plan so reviewers
  see the monthly $ delta of a change alongside the resource counts. Runs off the
  same `tfplan.json` the dashboard already produces; Infracost CLI is free and
  its cost data is public (a self-hosted/CLI setup needs no paid Cloud account).
  Deliberately out of scope for the current dashboard (the handoff excluded it).
- **Multi-region / DR**, **Front Door + WAF**, and **Entra-only SQL auth** — see
  Known limitations above.

---

## Local development

```bash
cd app
python -m venv .venv && source .venv/bin/activate   # or .venv\Scripts\activate on Windows
pip install -r requirements.txt
pip install flake8 pytest
export DB_CONNECTION_STRING="..."   # optional; otherwise read from Key Vault
flake8 . && pytest tests/
python app.py                       # http://localhost:8000
```
