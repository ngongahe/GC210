<#
    GC210 - Amorcage DC01 (execute par la Custom Script Extension)
    Promotion non interactive de corp.local, puis reprise post-redemarrage
    pour executer les scripts DE01 (01, 02, audit). Laboratoire ISOLE.
#>
param([Parameter(Mandatory)][string]$ScriptsBaseUrl)
$ErrorActionPreference = 'Stop'

$dir = 'C:\GC210'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# 1. Telecharger les scripts DE01
foreach ($f in 'Lab-Config.ps1','01-DC01-Comptes-AD.ps1','02-DC01-Affaiblir-LDAP.ps1','00-Prerequis.ps1', 'Sysmon64.exe', 'sysmonconfig.xml') {
  Invoke-WebRequest -UseBasicParsing "$ScriptsBaseUrl/$f" -OutFile "$dir\$f"
}
# Neutraliser le garde-fou interactif (automatisation)
Add-Content "$dir\Lab-Config.ps1" "`nfunction Confirm-LabExecution { param([string]`$n) }"

# 2. Promotion de la foret (non interactive, sans redemarrage immediat)
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
Import-Module ADDSDeployment
$dsrm = ConvertTo-SecureString '__REDACTED__' -AsPlainText -Force   # fictif (laboratoire)
Install-ADDSForest -DomainName 'corp.local' -DomainNetbiosName 'CORP' `
  -InstallDns -SafeModeAdministratorPassword $dsrm -Force -NoRebootOnCompletion

# 3. Tache de reprise apres redemarrage : configure les faiblesses annuaire
$resume = @'
Set-Location C:\GC210
try {
  .\01-DC01-Comptes-AD.ps1
  .\02-DC01-Affaiblir-LDAP.ps1
  .\00-Prerequis.ps1 -Task AuditSysmon
} finally {
  Unregister-ScheduledTask -TaskName GC210-Resume -Confirm:$false -ErrorAction SilentlyContinue
}
'@
$resume | Out-File "$dir\resume.ps1" -Encoding utf8
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -File C:\GC210\resume.ps1'
$trg = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName GC210-Resume -Action $act -Trigger $trg -RunLevel Highest -User SYSTEM -Force | Out-Null

# 4. Redemarrer pour finaliser la promotion (la tache de reprise prend le relais)
Restart-Computer -Force
