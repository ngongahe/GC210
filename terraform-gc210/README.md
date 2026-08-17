# GC210 — Socle Terraform du laboratoire Azure

> Déploie un laboratoire Active Directory **volontairement vulnérable** en **environnement isolé**. Ne pas exposer à Internet ; ne pas réutiliser en production.

## Contenu

| Fichier | Rôle |
|---|---|
| `providers.tf` | Fournisseurs (azurerm ~> 4.0) |
| `variables.tf` | Variables (région, adressage, tailles, options) |
| `network.tf` | RG, VNet, sous-réseaux, NSG, Bastion, VPN P2S (optionnel) |
| `compute.tf` | VM DC01/SRV01/WS01 + amorçage par Custom Script Extension |
| `main.tf` | Point d'entrée (Terraform fusionne tous les `.tf`) |
| `bootstrap-dc.ps1` / `-srv.ps1` / `-ws.ps1` | Amorçage par rôle (promotion, jonction, scripts DE01) |
| `environment.yaml` | Définition d'environnement Azure Deployment Environments (runner Terraform) |

## Prérequis d'amorçage

Héberger, à l'URL `scripts_base_url`, les fichiers `bootstrap-*.ps1` **et** les scripts DE01
(`Lab-Config.ps1`, `00-Prerequis.ps1`, `01-DC01-Comptes-AD.ps1`, `02-DC01-Affaiblir-LDAP.ps1`,
`03-SRV01-Web-Fichiers.ps1`). Options : *raw* GitHub (dépôt privé + token) ou compte de stockage Azure (URL SAS).

## Usage local (hors Dev Center)

```bash
export TF_VAR_admin_password='ChangezMoi_#2026!'
terraform init
terraform apply \
  -var="scripts_base_url=https://<host>/gc210-scripts" \
  -var="enable_vpn=false" \
  -var="deploy_ws=true"
```

Administrer ensuite les VM via **Azure Bastion**. Après montage, passer la règle NSG
`deny-internet-out` à `Deny` (dans `network.tf`) et `terraform apply`.

## Réserves

- **Provisioning AD** : promotion et jonctions impliquent des redémarrages, gérés ici par une
  tâche de reprise au démarrage. Ce socle convient à un **montage supervisé** ; pour une robustesse
  maximale (reprise, idempotence), envisager **Ansible/WinRM** (patron Adaz/GOAD).
- **Secrets** : `admin_password` transite par `protected_settings` (masqué) pour la jonction ;
  ne jamais committer de secret. Le mot de passe DSRM est fictif (laboratoire).
- **Modèle mutualisé** : DC/SRV en `B4ms` pour l'usage concurrent ; surveiller la charge et le
  seuil de verrouillage du compte de spraying.
