# GC210 - Laboratoire Azure - Variables

variable "location" {
  type        = string
  default     = "canadacentral"
  description = "Region Azure."
}

variable "rg_name" {
  type        = string
  default     = "rg-gc210-lab"
  description = "Groupe de ressources."
}

variable "admin_username" {
  type        = string
  default     = "azadmin"
  description = "Administrateur local des VM."
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Mot de passe administrateur local fort. Fournir via TF_VAR_admin_password."
}

# --- Adressage ---
variable "addr_vnet" {
  type    = string
  default = "10.10.0.0/16"
}

variable "addr_lab" {
  type    = string
  default = "10.10.10.0/24"
}

variable "addr_bastion" {
  type    = string
  default = "10.10.250.0/26" # sous-reseau impose : AzureBastionSubnet
}

variable "addr_gw" {
  type    = string
  default = "10.10.255.0/27" # sous-reseau impose : GatewaySubnet
}

variable "p2s_pool" {
  type    = string
  default = "172.16.0.0/24"
}

# --- IP statiques des cibles ---
variable "ip_dc" {
  type    = string
  default = "10.10.10.10"
}

variable "ip_srv" {
  type    = string
  default = "10.10.10.20"
}

variable "ip_ws" {
  type    = string
  default = "10.10.10.30"
}

# --- Tailles de VM (mutualise : DC/SRV en B4ms pour l'usage concurrent) ---
variable "size_dc" {
  type    = string
  default = "Standard_B2ms"
}

variable "size_srv" {
  type    = string
  default = "Standard_B2ms"
}

variable "size_ws" {
  type    = string
  default = "Standard_B4ms"
}

# --- Options ---
variable "enable_vpn" {
  type        = bool
  default     = false
  description = "Deployer la passerelle VPN P2S (long ~30-45 min)."
}

variable "deploy_ws" {
  type        = bool
  default     = true
  description = "Deployer WS01 (poste foothold). Optionnel en modele mutualise."
}

variable "scripts_base_url" {
  type        = string
  default     = "https://raw.githubusercontent.com/ngongahe/GC210/main/scripts"
  description = "URL de base (raw GitHub ou stockage SAS) hebergeant bootstrap-*.ps1 et les scripts DE01."
}

variable "image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
  description = "Image Windows Server (licence incluse au tarif Azure)."
}

variable "tags" {
  type = map(string)
  default = {
    cours          = "GC210"
    usage          = "laboratoire-isole"
    ne_pas_exposer = "internet"
  }
}