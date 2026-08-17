# GC210 - Laboratoire Azure - Point d'entree
#
# Terraform charge automatiquement TOUS les fichiers .tf de ce dossier :
#   providers.tf  -> fournisseurs (azurerm)
#   variables.tf  -> variables d'entree
#   network.tf    -> RG, VNet, sous-reseaux, NSG, Bastion, VPN (optionnel)
#   compute.tf    -> VM DC01/SRV01/WS01 + amorcage (Custom Script Extension)
#
# Ce fichier sert de point d'entree (templatePath dans environment.yaml pour ADE).
# Aucune ressource additionnelle n'est requise ici.