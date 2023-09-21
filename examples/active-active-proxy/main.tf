# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

resource "random_string" "friendly_name" {
  length  = 4
  upper   = false
  numeric = false
  special = false
}

# Store TFE License as secret
# ---------------------------
module "secrets" {
  source = "../../fixtures/secrets"

  key_vault_id = var.key_vault_id
  tfe_license = {
    name = "tfe-license-${random_string.friendly_name.id}"
    path = var.license_file
  }
}

# Bastion VM
# ----------
module "bastion_vm" {
  source = "../../fixtures/bastion_vm"

  bastion_user         = "bastionuser"
  bastion_subnet_cidr  = "10.0.16.0/20"
  friendly_name_prefix = local.friendly_name_prefix
  location             = var.location
  network_allow_range  = var.network_allow_range
  resource_group_name  = local.resource_group_name
  ssh_public_key       = data.azurerm_key_vault_secret.bastion_public_ssh_key.value
  virtual_network_name = module.active_active.network.network.name
  tags                 = var.tags
}

# MITM Proxy
# ----------
module "test_proxy" {
  source = "../../fixtures/test_proxy"

  friendly_name_prefix             = local.friendly_name_prefix
  key_vault_id                     = var.key_vault_id
  location                         = var.location
  mitmproxy_ca_certificate_secret  = data.azurerm_key_vault_secret.ca_certificate.id
  mitmproxy_ca_private_key_secret  = data.azurerm_key_vault_secret.ca_key.id
  proxy_public_ssh_key_secret_name = data.azurerm_key_vault_secret.proxy_public_ssh_key.value
  proxy_subnet_cidr                = local.network_proxy_subnet_cidr
  proxy_user                       = local.proxy_user
  resource_group_name              = local.resource_group_name
  virtual_network_name             = module.active_active.network.network.name
  tags                             = var.tags
}

# Active/Active TFE Architecture
# ------------------------------
module "active_active" {
  source = "../../"

  domain_name             = var.domain_name
  friendly_name_prefix    = local.friendly_name_prefix
  iact_subnet_list        = ["${module.bastion_vm.private_ip}/32"]
  location                = var.location
  resource_group_name_dns = var.resource_group_name_dns

  # Bootstrapping resources
  tfe_license_secret_id       = module.secrets.tfe_license_secret_id
  tls_bootstrap_cert_pathname = "/var/lib/terraform-enterprise/certificate.pem"
  tls_bootstrap_key_pathname  = "/var/lib/terraform-enterprise/key.pem"
  vm_certificate_secret       = data.azurerm_key_vault_secret.vm_certificate
  vm_key_secret               = data.azurerm_key_vault_secret.vm_key

  # Behind proxy information
  ca_certificate_secret = data.azurerm_key_vault_secret.ca_certificate
  proxy_ip              = module.test_proxy.private_ip
  proxy_port            = local.proxy_port

  # Private Active / Active Scenario
  create_bastion             = false
  distribution               = "rhel"
  production_type            = "external"
  load_balancer_public       = false
  load_balancer_type         = "load_balancer"
  redis_rdb_backup_enabled   = true
  redis_rdb_backup_frequency = 60
  redis_use_password_auth    = true
  redis_use_tls              = true
  vm_image_id                = "rhel"
  vm_node_count              = 2
  vm_sku                     = "Standard_D32a_v4"
  tags                       = var.tags
}