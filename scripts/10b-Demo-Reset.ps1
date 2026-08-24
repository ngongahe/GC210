<#
    GC210 - 10b-Demo-Reset.ps1
    Annule l'enrichissement de demonstration (10-Demo-Enrichissement.ps1).
    A EXECUTER SUR DC01 (via az vm run-command, methode fichier @).

    SUPPRIME : les 4 GPO de demo (dont le cpassword dans SYSVOL), puis l'OU
               _GC210_Demo en cascade (50 users, 15 groupes, 15 ordis fictifs,
               comptes de service, gMSA, helpdesk).

    NE TOUCHE JAMAIS :
      - _GC210_Scenario (comptes du Devoir)
      - WS02 (machine reelle : deplacee HORS de _GC210_Demo avant la suppression)
      - la cle racine KDS (inoffensive, conservee)

    Effets hors DC a rejouer apres (autres machines) :
      - SRV01 : Remove-LocalGroupMember Administrators 'CORP\helpdesk'
      - WS02  : gpupdate /force  (retablit pare-feu + admins locaux)
#>
param([switch]$Force)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
Import-Module GroupPolicy

$DomainDN = 'DC=corp,DC=local'
function Log($s,$m){ Write-Host ("[{0}] {1}" -f $s,$m) }

if(-not $Force){
  Log '!' "Ce script SUPPRIME toute la demo (_GC210_Demo + GPO). Relancez avec -Force pour confirmer."
  return
}

# ------------------------------------------------------------
# 1. Proteger WS02 : le sortir de _GC210_Demo avant toute suppression
# ------------------------------------------------------------
$ws2 = Get-ADComputer -Filter "Name -eq 'WS02'" -EA SilentlyContinue
if($ws2 -and $ws2.DistinguishedName -like "*_GC210_Demo*"){
  Move-ADObject -Identity $ws2.DistinguishedName -TargetPath "CN=Computers,$DomainDN"
  Log '+' "WS02 deplace hors de _GC210_Demo (vers CN=Computers) - preserve"
} elseif($ws2){ Log '=' "WS02 hors de _GC210_Demo - OK" } else { Log '=' "WS02 absent - rien a proteger" }

# ------------------------------------------------------------
# 2. Supprimer les 4 GPO de demo (retire aussi le cpassword de SYSVOL)
# ------------------------------------------------------------
foreach($g in 'Demo-FirewallOff','Demo-LogonScript','Demo-GPPSecret','Demo-HelpdeskLocalAdmin'){
  if(Get-GPO -Name $g -EA SilentlyContinue){
    Remove-GPO -Name $g -EA SilentlyContinue
    Log '+' "GPO supprimee (+ SYSVOL) : $g"
  } else { Log '=' "GPO absente : $g" }
}

# ------------------------------------------------------------
# 3. Supprimer l'OU _GC210_Demo en cascade
#    (leve la protection accidentelle sur tous les objets d'abord)
# ------------------------------------------------------------
$demo = Get-ADOrganizationalUnit -Filter "Name -eq '_GC210_Demo'" -EA SilentlyContinue
if($demo){
  Get-ADObject -SearchBase $demo.DistinguishedName -Filter * -EA SilentlyContinue |
    Set-ADObject -ProtectedFromAccidentalDeletion $false -EA SilentlyContinue
  Remove-ADOrganizationalUnit -Identity $demo.DistinguishedName -Recursive -Confirm:$false
  Log '+' "OU _GC210_Demo supprimee en cascade (users, groupes, ordis, svc, gMSA, helpdesk)"
} else { Log '=' "OU _GC210_Demo absente - deja nettoyee" }

# ------------------------------------------------------------
# 4. Verification
# ------------------------------------------------------------
$reste = Get-ADOrganizationalUnit -Filter "Name -eq '_GC210_Demo'" -EA SilentlyContinue
$scen  = Get-ADOrganizationalUnit -Filter "Name -eq '_GC210_Scenario'" -EA SilentlyContinue
Log ($(if($reste){'!'}else{'+'})) ("_GC210_Demo : " + $(if($reste){'ENCORE PRESENTE'}else{'supprimee'}))
Log ($(if($scen){'+'}else{'!'}))  ("_GC210_Scenario : " + $(if($scen){'intacte (comptes du Devoir preserves)'}else{'ABSENTE (anormal !)'}))
Log '=' "Suite : (SRV01) Remove-LocalGroupMember Administrators 'CORP\helpdesk' ; (WS02) gpupdate /force"