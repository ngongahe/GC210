# GC210 – Devoir 01 — Montage du laboratoire (scripts PowerShell)

> **Document enseignant.** Ces scripts construisent un environnement **volontairement vulnérable**, destiné à un **laboratoire isolé** (aucune connectivité vers un réseau réel). Ne jamais exécuter en production. Mots de passe **fictifs**, à adapter dans `Lab-Config.ps1`.

## Prérequis

- Domaine `corp.local` déjà promu sur `DC01` ; `SRV01` et `WS01` **joints au domaine**.
- Sur `DC01` : module `ActiveDirectory` (RSAT-AD-PowerShell), droits d'administration du domaine.
- Sur `SRV01` : droits d'administration locale ; connectivité vers `DC01`.
- Exécuter PowerShell **en tant qu'administrateur**.
- Placer `Lab-Config.ps1` **dans le même dossier** que les scripts sur chaque machine.

## Ordre d'exécution

| Étape | Machine | Script | Effet |
|---|---|---|---|
| 0a | future `DC01` | `00-Prerequis.ps1 -Task DcPromo` | Promotion de la forêt `corp.local` (redémarre) |
| 0b | `SRV01`, `WS01` | `00-Prerequis.ps1 -Task JoinDomain` | Jonction au domaine (redémarre) |
| 1 | `DC01` | `01-DC01-Comptes-AD.ps1` | Comptes fictifs, AS-REP, SPN, délégation contrainte, ACL DCSync, MAQ |
| 2 | `DC01` | `02-DC01-Affaiblir-LDAP.ps1` | Désactive signature/channel binding LDAP (**redémarrer ensuite**) |
| 3 | `SRV01` | `03-SRV01-Web-Fichiers.ps1` | IIS+Fichiers, partages, `web.config` planté, admin local `svc_web`, session `adm_files`, SMB non signé |
| 4 | `DC01`, `SRV01` | `00-Prerequis.ps1 -Task AuditSysmon` | Audit avancé, ligne de commande 4688, Sysmon (si fourni) |
| 5 | `DC01` puis `SRV01` | `99-Verifier.ps1` | Vérifie la présence des faiblesses attendues |
| — | `DC01`, `SRV01` | `98-Nettoyage.ps1 -Scope DC` / `-Scope SRV` | Réinitialisation entre cohortes (retire les faiblesses, restaure les signatures) |

> Après l'étape 2, **redémarrer `DC01`** (ou le service NTDS) pour appliquer la configuration LDAP.

## Personnalisation

- Tous les noms/mots de passe : `Lab-Config.ps1`.
- Cible de la délégation contrainte : variable `$DelegationSPN` (par défaut `CIFS/dc01.corp.local` ; alternatives `LDAP/dc01.corp.local`, `HOST/dc01.corp.local`).

## Faiblesses installées (rappel)

- Spraying (`p.gagnon`), AS-REP (`svc_legacy`), Kerberoasting + `web.config` (`svc_web`).
- Délégation contrainte avec transition de protocole (`svc_web` → `CIFS/DC01`).
- Session périodique capturable (`adm_files`) + droit de réplication (DCSync), **hors** Domain Admins.
- Relais NTLM → LDAP fonctionnel (`DC01` sans signature/CBT) ; RBCD via MachineAccountQuota.

## Avertissement

Environnement d'entraînement **jetable**. À l'issue du cours, détruire les machines virtuelles. Ne pas réutiliser ces comptes/mots de passe ailleurs.
