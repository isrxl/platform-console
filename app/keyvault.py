"""Key Vault access via Managed Identity.

Uses DefaultAzureCredential, scoped to the user-assigned managed identity when
AZURE_CLIENT_ID is present (the App Service case). No secrets are ever stored
in code or config — they are fetched at runtime over the private endpoint.
"""
import functools

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

from config import Config


@functools.lru_cache(maxsize=1)
def _credential():
    if Config.AZURE_CLIENT_ID:
        return DefaultAzureCredential(
            managed_identity_client_id=Config.AZURE_CLIENT_ID
        )
    return DefaultAzureCredential()


@functools.lru_cache(maxsize=1)
def _client():
    if not Config.KEY_VAULT_URL:
        raise RuntimeError("KEY_VAULT_URL is not configured")
    return SecretClient(vault_url=Config.KEY_VAULT_URL, credential=_credential())


def get_secret(name):
    """Return a secret value by name."""
    return _client().get_secret(name).value


def list_secret_expiries():
    """Return [{name, expires_on}] for all secrets in the vault.

    expires_on is an ISO-8601 string or None. Reads only properties — secret
    values are never retrieved here.
    """
    results = []
    for prop in _client().list_properties_of_secrets():
        expires = prop.expires_on.isoformat() if prop.expires_on else None
        results.append({"name": prop.name, "expires_on": expires})
    return results
