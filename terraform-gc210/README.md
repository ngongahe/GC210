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
export TF_VAR_local_admin_password='<mot-de-passe-admin-local>'
export TF_VAR_domain_join_password='<mot-de-passe-jonction-domaine>'
export TF_VAR_dsrm_password='<mot-de-passe-dsrm>'
terraform init
terraform apply \
  -var="scripts_base_url=https://<host>/gc210-scripts" \
  -var="nsg_hardened=false" \
  -var="enable_vpn=false" \
  -var="deploy_ws=true"
```

Administrer ensuite les VM via **Azure Bastion**. Le mode de montage (`nsg_hardened=false`) autorise
temporairement P2S entrant et Internet sortant (la sortie est permise par defaut en l'absence de
regle `Deny`). Apres validation complete du laboratoire, recreer
un plan avec `nsg_hardened=true` et `allow_bootstrap_internet=false`, puis l'appliquer pour activer
les regles AD limitees et fermer la sortie Internet. L'ouverture HTTPS cible le tag de service
`Internet` car NSG ne filtre pas les noms DNS GitHub.

Fournir `bastion_admin_principal_ids` avec les IDs Entra des administrateurs autorises. Ils
recoivent `Reader` sur Bastion et `Virtual Machine Administrator Login` sur le groupe de ressources.

## Réserves

- **Provisioning AD** : promotion et jonctions impliquent des redémarrages, gérés ici par une
  tâche de reprise au démarrage. Ce socle convient à un **montage supervisé** ; pour une robustesse
  maximale (reprise, idempotence), envisager **Ansible/WinRM** (patron Adaz/GOAD).
- **Secrets** : les mots de passe local, de jonction et DSRM sont distincts et ne doivent jamais
  être commités. Les secrets de jonction et DSRM transitent par `protected_settings` (masqués).
- **Modèle mutualisé** : DC/SRV en `B4ms` pour l'usage concurrent ; surveiller la charge et le
  seuil de verrouillage du compte de spraying.
