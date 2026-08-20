# GC210 - Laboratoire Azure - Reseau, NSG, Bastion, VPN

resource "azurerm_resource_group" "lab" {
  name     = var.rg_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-gc210"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [var.addr_vnet]
  # DNS pointe vers le DC (IP statique connue) : les membres resolvent le domaine.
  dns_servers = [var.ip_dc]
  tags        = var.tags
}

resource "azurerm_subnet" "lab" {
  name                 = "snet-lab"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.addr_lab]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet" # nom impose
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.addr_bastion]
}

resource "azurerm_subnet" "gateway" {
  count                = var.enable_vpn ? 1 : 0
  name                 = "GatewaySubnet" # nom impose
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.addr_gw]
}

# --- NSG du sous-reseau laboratoire ---
resource "azurerm_network_security_group" "lab" {
  name                = "nsg-lab"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags

  security_rule {
    name                       = "allow-students-p2s"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = var.p2s_pool
    source_port_range          = "*"
    destination_address_prefix = var.addr_lab
    destination_port_range     = "*"
  }

  # Coupure Internet sortant des cibles : ACTIVER APRES le montage
  # (mettre access = "Deny" une fois les scripts et Sysmon telecharges).
  security_rule {
    name                       = "deny-internet-out"
    priority                   = 4096
    direction                  = "Outbound"
    access                     = "Allow" # -> passer a "Deny" apres montage
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "Internet"
    destination_port_range     = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "lab" {
  subnet_id                 = azurerm_subnet.lab.id
  network_security_group_id = azurerm_network_security_group.lab.id
}

# --- Azure Bastion (administration) ---
resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "bastion" {
  name                = "bastion-gc210"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "Standard"
  tags                = var.tags

  ip_configuration {
    name                 = "config"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

# --- VPN Point-to-Site (optionnel ; authentification par certificat) ---
resource "azurerm_public_ip" "vpngw" {
  count               = var.enable_vpn ? 1 : 0
  name                = "pip-vpngw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "vpngw" {
  count               = var.enable_vpn ? 1 : 0
  name                = "vpngw-gc210"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1"
  tags                = var.tags

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpngw[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway[0].id
  }

  vpn_client_configuration {
    address_space        = [var.p2s_pool]
    vpn_client_protocols = ["OpenVPN"]
    # Certificat racine : coller la donnee base64 (voir gen-vpn-certs.sh).
    # root_certificate {
    #   name             = "GC210-Root"
    #   public_cert_data = file("${path.module}/caCert_base64.txt")
    # }
  }
}