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

  dynamic "security_rule" {
    for_each = var.nsg_hardened ? [] : [1]
    content {
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
  }

  dynamic "security_rule" {
    for_each = var.nsg_hardened ? [1] : []
    content {
      name                       = "allow-p2s-dns-udp"
      priority                   = 200
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Udp"
      source_address_prefix      = var.p2s_pool
      source_port_range          = "*"
      destination_address_prefix = var.addr_lab
      destination_port_range     = "53"
    }
  }

  dynamic "security_rule" {
    for_each = var.nsg_hardened ? [1] : []
    content {
      name                       = "allow-p2s-dns-tcp"
      priority                   = 201
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = var.p2s_pool
      source_port_range          = "*"
      destination_address_prefix = var.addr_lab
      destination_port_range     = "53"
    }
  }

  dynamic "security_rule" {
    for_each = var.nsg_hardened ? [1] : []
    content {
      name                       = "allow-p2s-admin-ad"
      priority                   = 210
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = var.p2s_pool
      source_port_range          = "*"
      destination_address_prefix = var.addr_lab
      destination_port_ranges    = ["88", "135", "389", "445", "464", "636", "3268", "3269", "3389", "5985", "5986", "49152-65535"]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "lab" {
  subnet_id                 = azurerm_subnet.lab.id
  network_security_group_id = azurerm_network_security_group.lab.id
}

# --- Azure Bastion (administration) ---
resource "azurerm_public_ip" "bastion" {
  count               = var.enable_bastion ? 1 : 0
  name                = "pip-bastion"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "bastion" {
  count               = var.enable_bastion ? 1 : 0
  name                   = "bastion-gc210"
  location               = azurerm_resource_group.lab.location
  resource_group_name    = azurerm_resource_group.lab.name
  sku                    = "Standard"
  copy_paste_enabled     = true
  file_copy_enabled      = false
  ip_connect_enabled     = false
  kerberos_enabled       = true
  shareable_link_enabled = false
  tunneling_enabled      = false
  tags                   = var.tags

  ip_configuration {
    name                 = "config"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}

resource "azurerm_role_assignment" "bastion_reader" {
  for_each             = var.bastion_admin_principal_ids
  scope                = azurerm_bastion_host.bastion[0].id
  role_definition_name = "Reader"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "bastion_vm_admin" {
  for_each             = var.bastion_admin_principal_ids
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Virtual Machine Administrator Login"
  principal_id         = each.value
}

# --- VPN Point-to-Site (optionnel ; authentification par certificat) ---
resource "azurerm_public_ip" "vpngw" {
  count               = var.enable_vpn ? 1 : 0
  name                = "pip-vpngw"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]   # zone-redundant, requis par VpnGw1AZ
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "vpngw" {
  count               = var.enable_vpn ? 1 : 0
  name                = "vpngw-gc210"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1AZ"
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
    root_certificate {
       name             = "GC210-Root"
       public_cert_data = file("${path.module}/caCert_base64.txt")
     }
  }
}