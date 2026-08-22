# GC210 - Laboratoire Azure - VM et amorcage (Custom Script Extension)
#
# Amorcage : chaque VM telecharge un script d'amorcage (bootstrap-*.ps1) depuis
# var.scripts_base_url, qui enchaine les scripts DE01 dans le bon ordre.
#   - DC01 : promotion (00 DcPromo) + faiblesses annuaire (01) + affaiblissement LDAP (02)
#   - SRV01: jonction (00 JoinDomain) + faiblesses hote (03)
#   - WS01 : jonction (00 JoinDomain)
# L'ordonnancement (DC avant membres) est assure par depends_on.
#
# NOTE PROVISIONING : la promotion AD implique des redemarrages ; l'extension
# Custom Script gere un seul flux. Pour une robustesse maximale (redemarrages,
# reprise), envisager Ansible/WinRM (patron Adaz/GOAD) ou DSC. Le present socle
# convient a un montage supervise ; valider le premier deploiement.

locals {
  ext_publisher = "Microsoft.Compute"
  ext_type      = "CustomScriptExtension"
  ext_version   = "1.10"
}

# ---------------- DC01 ----------------
resource "azurerm_network_interface" "dc" {
  name                = "nic-dc01"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags
  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.lab.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.ip_dc
  }
}

resource "azurerm_windows_virtual_machine" "dc" {
  name                  = "DC01"
  computer_name         = "DC01"
  resource_group_name   = azurerm_resource_group.lab.name
  location              = azurerm_resource_group.lab.location
  size                  = var.size_dc
  admin_username        = var.local_admin_username
  admin_password        = var.local_admin_password
  network_interface_ids = [azurerm_network_interface.dc.id]
  tags                  = var.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }
  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "dc" {
  virtual_machine_id    = azurerm_windows_virtual_machine.dc.id
  location              = azurerm_resource_group.lab.location
  enabled               = true
  daily_recurrence_time = "0100"
  timezone              = "Eastern Standard Time"

  notification_settings {
    enabled = false
  }
}

resource "azurerm_virtual_machine_extension" "dc_bootstrap" {
  name                       = "bootstrap-dc"
  virtual_machine_id         = azurerm_windows_virtual_machine.dc.id
  publisher                  = local.ext_publisher
  type                       = local.ext_type
  type_handler_version       = local.ext_version
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = false

  settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Bypass -Command \"Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses 168.63.129.16 -ErrorAction SilentlyContinue }; Start-Sleep 10; Invoke-WebRequest -UseBasicParsing '${var.scripts_base_url}/bootstrap-dc.ps1' -OutFile C:\\bootstrap-dc.ps1; & C:\\bootstrap-dc.ps1 -ScriptsBaseUrl '${var.scripts_base_url}'\""

  })
}

# ---------------- SRV01 ----------------
resource "azurerm_network_interface" "srv" {
  name                = "nic-srv01"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags
  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.lab.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.ip_srv
  }
}

resource "azurerm_windows_virtual_machine" "srv" {
  name                  = "SRV01"
  computer_name         = "SRV01"
  resource_group_name   = azurerm_resource_group.lab.name
  location              = azurerm_resource_group.lab.location
  size                  = var.size_srv
  admin_username        = var.local_admin_username
  admin_password        = var.local_admin_password
  network_interface_ids = [azurerm_network_interface.srv.id]
  tags                  = var.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }
  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "srv" {
  virtual_machine_id    = azurerm_windows_virtual_machine.srv.id
  location              = azurerm_resource_group.lab.location
  enabled               = true
  daily_recurrence_time = "0100"
  timezone              = "Eastern Standard Time"

  notification_settings {
    enabled = false
  }
}

resource "azurerm_virtual_machine_extension" "srv_bootstrap" {
  name                       = "bootstrap-srv"
  virtual_machine_id         = azurerm_windows_virtual_machine.srv.id
  publisher                  = local.ext_publisher
  type                       = local.ext_type
  type_handler_version       = local.ext_version
  auto_upgrade_minor_version = true
  # S'assurer que le DC est promu/configure avant la jonction.
  depends_on = [azurerm_virtual_machine_extension.dc_bootstrap]

  # protected_settings : masque la commande et le mot de passe de jonction.
  protected_settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Bypass -Command \"Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses 168.63.129.16 -ErrorAction SilentlyContinue }; Start-Sleep 10; Invoke-WebRequest -UseBasicParsing '${var.scripts_base_url}/bootstrap-srv.ps1' -OutFile C:\\bootstrap-srv.ps1; if ((Get-FileHash -Algorithm SHA256 -LiteralPath C:\\bootstrap-srv.ps1).Hash.ToLower() -ne 'fcc459445ad15caa199fcb2b351f22e238cbd03fe1541ad9e4a788052768ea84') { throw 'Hash SHA-256 invalide pour bootstrap-srv.ps1.' }; & C:\\bootstrap-srv.ps1 -ScriptsBaseUrl '${var.scripts_base_url}' -DomainJoinUsername '${var.domain_join_username}' -DomainPassword '${var.domain_join_password}'\""
  })
}

# ---------------- WS01 (optionnel) ----------------
resource "azurerm_network_interface" "ws" {
  count               = var.deploy_ws ? 1 : 0
  name                = "nic-ws01"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags
  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.lab.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.ip_ws
  }
}

resource "azurerm_windows_virtual_machine" "ws" {
  count                 = var.deploy_ws ? 1 : 0
  name                  = "WS01"
  computer_name         = "WS01"
  resource_group_name   = azurerm_resource_group.lab.name
  location              = azurerm_resource_group.lab.location
  size                  = var.size_ws
  admin_username        = var.local_admin_username
  admin_password        = var.local_admin_password
  network_interface_ids = [azurerm_network_interface.ws[0].id]
  tags                  = var.tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }
  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "ws" {
  count                 = var.deploy_ws ? 1 : 0
  virtual_machine_id    = azurerm_windows_virtual_machine.ws[0].id
  location              = azurerm_resource_group.lab.location
  enabled               = true
  daily_recurrence_time = "0100"
  timezone              = "Eastern Standard Time"

  notification_settings {
    enabled = false
  }
}

resource "azurerm_virtual_machine_extension" "ws_bootstrap" {
  count                      = var.deploy_ws ? 1 : 0
  name                       = "bootstrap-ws"
  virtual_machine_id         = azurerm_windows_virtual_machine.ws[0].id
  publisher                  = local.ext_publisher
  type                       = local.ext_type
  type_handler_version       = local.ext_version
  auto_upgrade_minor_version = true
  depends_on                 = [azurerm_virtual_machine_extension.dc_bootstrap]

  protected_settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Bypass -Command \"Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses 168.63.129.16 -ErrorAction SilentlyContinue }; Start-Sleep 10; Invoke-WebRequest -UseBasicParsing '${var.scripts_base_url}/bootstrap-ws.ps1' -OutFile C:\\bootstrap-ws.ps1; if ((Get-FileHash -Algorithm SHA256 -LiteralPath C:\\bootstrap-ws.ps1).Hash.ToLower() -ne 'b76fe81ad51e64ffb403f4a07921c79b9371f54771dfd482963f0b7d9f348888') { throw 'Hash SHA-256 invalide pour bootstrap-ws.ps1.' }; & C:\\bootstrap-ws.ps1 -ScriptsBaseUrl '${var.scripts_base_url}' -DomainJoinUsername '${var.domain_join_username}' -DomainPassword '${var.domain_join_password}'\""
  })
}

# ---------------- Sorties ----------------
output "dc_private_ip" { value = var.ip_dc }
output "srv_private_ip" { value = var.ip_srv }
output "ws_private_ip" { value = var.deploy_ws ? var.ip_ws : "non deploye" }
output "bastion_name" { value = azurerm_bastion_host.bastion.name }
output "note" {
  value = "Administrer via Bastion. Activer 'deny-internet-out' apres montage. Ne pas exposer a Internet."
}