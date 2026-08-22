# GC210 - Demarrage automatique des VM (fenetre 17h-1h)
# ---------------------------------------------------------------------------
# Complete l'arret automatique (azurerm_dev_test_global_vm_shutdown_schedule a 0100).
# Deploie une Automation Account + un runbook Start-AzVM planifie a 17:00 (America/Toronto).
# A placer dans le dossier terraform-gc210/ (fusionne avec les autres .tf).
#
# PREREQUIS : les modules Az.Accounts et Az.Compute doivent etre disponibles dans
# l'Automation Account (ils le sont par defaut sur les comptes recents ; sinon les
# importer). Valider par un premier declenchement manuel du runbook.
# ---------------------------------------------------------------------------

variable "start_time" {
  type        = string
  default     = "2026-08-26T17:00:00-04:00"
  description = "Premiere occurrence du demarrage (RFC3339, 17:00 heure locale, dans le futur). Ex : 2026-08-26T17:00:00-04:00"
}

resource "azurerm_automation_account" "auto" {
  name                = "aa-gc210"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku_name            = "Basic"
  identity {
    type = "SystemAssigned"
  }
  tags = var.tags
}

# Droit de demarrer les VM du groupe de ressources
resource "azurerm_role_assignment" "auto_vm" {
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_automation_account.auto.identity[0].principal_id
}

resource "azurerm_automation_runbook" "start" {
  name                    = "Start-LabVMs"
  location                = azurerm_resource_group.lab.location
  resource_group_name     = azurerm_resource_group.lab.name
  automation_account_name = azurerm_automation_account.auto.name
  log_verbose             = false
  log_progress            = false
  runbook_type            = "PowerShell72"
  description             = "Demarre DC01, SRV01, WS01 (fenetre 17h-1h)"
  tags                    = var.tags

  content = <<-EOT
    Connect-AzAccount -Identity | Out-Null
    $rg = '${azurerm_resource_group.lab.name}'
    foreach ($vm in @('DC01','SRV01','WS01')) {
      Start-AzVM -ResourceGroupName $rg -Name $vm -NoWait -ErrorAction SilentlyContinue
    }
  EOT
}

resource "azurerm_automation_schedule" "daily_1700" {
  name                    = "Daily-1700"
  resource_group_name     = azurerm_resource_group.lab.name
  automation_account_name = azurerm_automation_account.auto.name
  frequency               = "Day"
  interval                = 1
  timezone                = "America/Toronto"
  start_time              = var.start_time
  description             = "Demarrage quotidien du laboratoire a 17h"
}

resource "azurerm_automation_job_schedule" "link" {
  resource_group_name     = azurerm_resource_group.lab.name
  automation_account_name = azurerm_automation_account.auto.name
  runbook_name            = azurerm_automation_runbook.start.name
  schedule_name           = azurerm_automation_schedule.daily_1700.name
}
