<#
    GC210 - Devoir 01 - Script 03 (a executer sur SRV01)
    ----------------------------------------------------------------------
    Configure SRV01 en serveur Web (IIS) + serveur de fichiers (SMB), et
    introduit les faiblesses cote hote :
      - pool d'application IIS execute sous svc_web
      - partages SMB Public et WebBackup (lecture Domain Users)
      - web.config plante exposant le mot de passe de svc_web (option 1)
      - svc_web administrateur local de SRV01
      - session periodique de adm_files (tache planifiee) capturable (option 5)
      - signature SMB non requise
    Prerequis : SRV01 joint au domaine ; droits Admin local ; comptes crees (script 01).
#>

#Requires -RunAsAdministrator
. "$PSScriptRoot\Lab-Config.ps1"
Confirm-LabExecution "03 - Web + Fichiers et faiblesses (SRV01)"

$pwdWeb = Get-LabPassword 'svc_web'
$pwdAdm = Get-LabPassword 'adm_files'

# --- 1. Roles IIS + serveur de fichiers -----------------------------------
Install-WindowsFeature Web-Server, Web-Mgmt-Tools, FS-FileServer -ErrorAction Stop | Out-Null
Import-Module WebAdministration
Write-Host "[+ ] Roles IIS et serveur de fichiers installes" -ForegroundColor Green

# --- 2. Pool d'application execute sous svc_web ----------------------------
$pool = 'GC210App'
if (-not (Test-Path "IIS:\AppPools\$pool")) { New-WebAppPool -Name $pool | Out-Null }
Set-ItemProperty "IIS:\AppPools\$pool" -Name processModel -Value @{
    userName     = "$LabDomainNB\svc_web"
    password     = $pwdWeb
    identitytype = 3   # SpecificUser
}
Write-Host "[+ ] Pool IIS '$pool' execute sous $LabDomainNB\svc_web" -ForegroundColor Green

# --- 3. Partages SMB -------------------------------------------------------
New-Item -Path 'C:\Shares\Public'    -ItemType Directory -Force | Out-Null
New-Item -Path 'C:\Shares\WebBackup' -ItemType Directory -Force | Out-Null
'Fichiers internes - usage laboratoire.' | Set-Content 'C:\Shares\Public\LISEZMOI.txt'

foreach ($s in @(
    @{ Name='Public';    Path='C:\Shares\Public' }
    @{ Name='WebBackup'; Path='C:\Shares\WebBackup' })) {
    if (-not (Get-SmbShare -Name $s.Name -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $s.Name -Path $s.Path -ReadAccess "$LabDomainNB\Domain Users" | Out-Null
    }
}
Write-Host "[+ ] Partages SMB Public et WebBackup crees (lecture Domain Users)" -ForegroundColor Green

# --- 4. web.config plante (option 1) : mot de passe svc_web en clair -------
$webconfig = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <connectionStrings>
    <add name="AppDB"
         connectionString="Server=$SRV_FQDN;Database=AppMetier;User Id=svc_web;Password=$pwdWeb;" />
  </connectionStrings>
  <appSettings>
    <add key="ServiceAccount" value="$LabDomainNB\svc_web" />
  </appSettings>
</configuration>
"@
Set-Content -Path 'C:\Shares\WebBackup\web.config' -Value $webconfig -Encoding UTF8
Write-Host "[+ ] web.config plante dans \\$SRV\WebBackup (mot de passe svc_web expose)" -ForegroundColor Green

# --- 5. svc_web et adm_files administrateur local de SRV01 ------------------------------
try {
    Add-LocalGroupMember -Group 'Administrators' -Member "$LabDomainNB\svc_web" -ErrorAction Stop
    Write-Host "[+ ] svc_web ajoute aux administrateurs locaux de SRV01" -ForegroundColor Green
} catch { Write-Host "[= ] svc_web deja admin local (ou erreur benigne)" -ForegroundColor DarkGray }

try {
    Add-LocalGroupMember -Group 'Administrators' -Member "$LabDomainNB\adm_files" -ErrorAction Stop
    Write-Host "[+ ] adm_files ajoute aux administrateurs locaux de SRV01" -ForegroundColor Green
} catch { Write-Host "[= ] adm_files deja admin local (ou erreur benigne)" -ForegroundColor DarkGray }

# --- 6. Session periodique de adm_files (option 5) -------------------------
#   Tache planifiee executee sous adm_files -> identifiants/tickets en memoire.
$action  = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c whoami > C:\Windows\Temp\admfiles.log'
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) `
             -RepetitionInterval (New-TimeSpan -Minutes 15)
Register-ScheduledTask -TaskName 'GC210-AdmSession' -Action $action -Trigger $trigger `
    -User "$LabDomainNB\adm_files" -Password $pwdAdm -RunLevel Highest -Force | Out-Null
Write-Host "[+ ] Tache 'GC210-AdmSession' (session periodique adm_files) enregistree" -ForegroundColor Green

# --- 7. Signature SMB non requise -----------------------------------------
Set-SmbServerConfiguration -RequireSecuritySignature $false -EnableSecuritySignature $false -Confirm:$false
Write-Host "[+ ] Signature SMB non requise sur SRV01" -ForegroundColor Green

Write-Host "`n[OK] SRV01 configure (Web + Fichiers + faiblesses)." -ForegroundColor Cyan
Write-Host "     Verification : 99-Verifier.ps1" -ForegroundColor Cyan
