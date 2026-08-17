# GC210 - Laboratoire Azure - Fournisseurs Terraform
# Socle IaC du laboratoire AD volontairement vulnerable (environnement ISOLE).

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  # Backend a activer pour Azure Deployment Environments / usage en equipe :
  # backend "azurerm" {}
}

provider "azurerm" {
  features {}
}