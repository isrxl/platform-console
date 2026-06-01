terraform {
  # State storage is bootstrapped manually (see README / handoff Section 4.2).
  # The state key is injected per environment by the pipeline at init time:
  #   terraform init -backend-config="key=prod/terraform.tfstate"
  #
  # Storage account / resource group / container are supplied via -backend-config
  # flags from GitHub secrets (TF_STATE_RG, TF_STATE_SA, TF_STATE_CONTAINER), which
  # keeps the random storage account suffix out of source control.
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "cdvlplatcone46dcefeb780"
    container_name       = "tfstate"
    use_azuread_auth     = true
  }
}
