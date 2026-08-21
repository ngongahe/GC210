<#
    GC210 - Amorcage SRV01 (Custom Script Extension)
    Attend le DC, joint corp.local, puis execute le script 03 (Web+Fichiers).
#>
param(
  [Parameter(Mandatory)][string]$ScriptsBaseUrl,
  [Parameter(Mandatory)][string]$DomainPassword
)
$ErrorActionPreference = 'Stop'

$dir = 'C:\GC210'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
foreach ($f in 'Lab-Config.ps1','03-SRV01-Web-Fichiers.ps1','00-Prerequis.ps1', 'Sysmon64.exe', 'sysmonconfig.xml' ) {
  Invoke-WebRequest -UseBasicParsing "$ScriptsBaseUrl/$f" -OutFile "$dir\$f"
}
Add-Content "$dir\Lab-Config.ps1" "`nfunction Confirm-LabExecution { param([string]`$n) }"

# Attendre que le DC (DNS/AD) reponde
$deadline = (Get-Date).AddMinutes(30)
do {
  Start-Sleep -Seconds 30
  $ok = Test-Connection -ComputerName 'corp.local' -Count 1 -Quiet -ErrorAction SilentlyContinue
} until ($ok -or (Get-Date) -gt $deadline)

# Jonction au domaine (compte Administrateur du domaine = admin local post-promo)
$cred = New-Object System.Management.Automation.PSCredential(
  'CORP\Administrateur', (ConvertTo-SecureString $DomainPassword -AsPlainText -Force))

# Tache de reprise post-redemarrage : execute le script 03
$resume = @'
Set-Location C:\GC210
try { .\03-SRV01-Web-Fichiers.ps1; .\00-Prerequis.ps1 -Task AuditSysmon }
finally { Unregister-ScheduledTask -TaskName GC210-Resume -Confirm:$false -ErrorAction SilentlyContinue }
'@
$resume | Out-File "$dir\resume.ps1" -Encoding utf8
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -File C:\GC210\resume.ps1'
Register-ScheduledTask -TaskName GC210-Resume -Action $act -Trigger (New-ScheduledTaskTrigger -AtStartup) `
  -RunLevel Highest -User SYSTEM -Force | Out-Null

Add-Computer -DomainName 'corp.local' -Credential $cred -Restart -Force
