"""Runtime configuration sourced entirely from environment / Key Vault.

Nothing here is hardcoded for a specific environment. App Service injects the
settings at deploy time (handoff Section 6.6); locally you can export the same
variables. Missing values degrade gracefully so the app still starts (required
for CI build validation) and the Platform Health tab reports the gap.
"""
import os


class Config:
    KEY_VAULT_URL = os.environ.get("KEY_VAULT_URL", "")
    ENVIRONMENT = os.environ.get("ENVIRONMENT", "local")
    APP_VERSION = os.environ.get("APP_VERSION", "dev-local")
    SEMANTIC_VERSION = os.environ.get("SEMANTIC_VERSION", "")
    DEPLOYED_AT = os.environ.get("DEPLOYED_AT", "")
    APPINSIGHTS_CONNECTION_STRING = os.environ.get(
        "APPLICATIONINSIGHTS_CONNECTION_STRING", ""
    )
    # Client ID of the user-assigned managed identity used to auth to Key Vault.
    AZURE_CLIENT_ID = os.environ.get("AZURE_CLIENT_ID", "")

    # Local-only escape hatch: skip Key Vault and use a direct connection string.
    DB_CONNECTION_STRING = os.environ.get("DB_CONNECTION_STRING", "")

    # Secret names seeded by the Terraform security module.
    DB_SECRET_NAME = "db-connection-string"
    APP_SECRET_NAME = "app-secret"
