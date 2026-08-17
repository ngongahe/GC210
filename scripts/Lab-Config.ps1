<#
    GC210 - Devoir 01 - Variables partagees du laboratoire
    ----------------------------------------------------------------------
    Environnement VOLONTAIREMENT VULNERABLE, destine a un laboratoire ISOLE.
    Ne jamais executer en production. Mots de passe FICTIFS : a adapter.

    Ce fichier est chargé par les autres scripts :
        . .\Lab-Config.ps1
#>

# --- Domaine ---------------------------------------------------------------
$Global:LabDomainDNS = 'corp.local'
$Global:LabDomainNB  = 'CORP'

# --- Hotes -----------------------------------------------------------------
$Global:DC        = 'DC01'
$Global:SRV       = 'SRV01'
$Global:DC_FQDN   = 'dc01.corp.local'
$Global:SRV_FQDN  = 'srv01.corp.local'

# --- Comptes fictifs (a adapter avant execution) ---------------------------
$Global:Accounts = @(
    @{ Sam='e.roy';      Name='Etienne Roy';       Pwd='Bienvenue2025';      Desc='Utilisateur initial (foothold WS01)' }
    @{ Sam='p.gagnon';   Name='Patrick Gagnon';    Pwd='Automne2025!';       Desc='Mot de passe faible (password spraying)' }
    @{ Sam='svc_legacy'; Name='Service Legacy';    Pwd='Hiver2019';          Desc='DONT_REQ_PREAUTH (AS-REP roasting)' }
    @{ Sam='svc_web';    Name='Service Web IIS';   Pwd='P@ssword1';    Desc='SPN HTTP, admin local SRV01, delegation contrainte' }
    @{ Sam='adm_files';  Name='Admin Fichiers';    Pwd='F1lesAdmin!2025';    Desc='Session periodique SRV01, droit de replication (DCSync), NON Domain Admin' }
    @{ Sam='da_admin';   Name='Domain Admin Lab';  Pwd='D0mainAdmin!Str0ng#2025'; Desc='Cible d usurpation S4U ; ne se connecte pas a SRV01' }
)

# --- Cible de la delegation contrainte (ajustable) -------------------------
#   CIFS/dc01.corp.local (recommande) | LDAP/dc01.corp.local | HOST/dc01.corp.local
$Global:DelegationSPN = "CIFS/$DC_FQDN"

# --- SPN du compte de service Web ------------------------------------------
$Global:WebSPN = "HTTP/$SRV_FQDN"

function Get-LabPassword([string]$Sam) {
    ($Global:Accounts | Where-Object { $_.Sam -eq $Sam }).Pwd
}

function Confirm-LabExecution([string]$ScriptName) {
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Yellow
    Write-Host " $ScriptName" -ForegroundColor Yellow
    Write-Host " ENVIRONNEMENT VOLONTAIREMENT VULNERABLE - LABORATOIRE ISOLE UNIQUEMENT" -ForegroundColor Yellow
    Write-Host " Ne pas executer en production." -ForegroundColor Yellow
    Write-Host "==================================================================" -ForegroundColor Yellow
    $r = Read-Host "Confirmer l'execution en laboratoire isole ? (oui/non)"
    if ($r -ne 'oui') { Write-Host "Annule." -ForegroundColor Red; exit 1 }
}
