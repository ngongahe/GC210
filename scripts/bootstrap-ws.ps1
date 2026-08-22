<#
    GC210 - Amorcage WS01 (Custom Script Extension)
    Depose l'outillage, attend le DC, joint corp.local (poste foothold),
    puis execute l'audit + Sysmon apres redemarrage. Laboratoire ISOLE.
#>
param(
  [Parameter(Mandatory)][string]$ScriptsBaseUrl,
  [Parameter(Mandatory)][string]$DomainJoinUsername,
  [Parameter(Mandatory)][string]$DomainPassword
)
$ErrorActionPreference = 'Stop'

# DNS Azure pour resoudre la source des scripts avant que le DC soit disponible.
Get-NetAdapter | Where-Object Status -eq 'Up' | Set-DnsClientServerAddress -ServerAddresses 168.63.129.16 -ErrorAction SilentlyContinue

$dir = 'C:\GC210'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$scriptsHost = ([System.Uri]$ScriptsBaseUrl).DnsSafeHost
$scriptsDeadline = (Get-Date).AddMinutes(10)
do {
  $scriptsDns = Resolve-DnsName -Name $scriptsHost -Type A -ErrorAction SilentlyContinue
  if (-not $scriptsDns) { Start-Sleep -Seconds 30 }
} until ($scriptsDns -or (Get-Date) -gt $scriptsDeadline)
if (-not $scriptsDns) { throw "Le nom $scriptsHost n'est pas resolvable dans le delai imparti." }

$expectedHashes = @{
  'Lab-Config.ps1'   = 'bf28b637698b8de434eb8ccea0314aeec94b781c9eb1407c379224cf1f1e5c71'
  '00-Prerequis.ps1' = 'ce3009f6d3ca6c600e5add26bb0e51a4a3545b431acc2dcbdeab18ef2ba9a48a'
  'Sysmon64.exe'     = 'a60aa845457406383277afdead35bd90c7804572b99901d239cc974841df2528'
  'sysmonconfig.xml' = '60b7b3950bd63b93ad8f6f275dce4bb932b09be16805d9dbf6cc34954a8699f2'
}
foreach ($f in 'Lab-Config.ps1','00-Prerequis.ps1', 'Sysmon64.exe', 'sysmonconfig.xml') {
  $destination = "$dir\$f"
  Invoke-WebRequest -UseBasicParsing "$ScriptsBaseUrl/$f" -OutFile $destination
  $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
  if ($actualHash -ne $expectedHashes[$f]) { throw "Hash SHA-256 invalide pour $f." }
}
Add-Content "$dir\Lab-Config.ps1" "`nfunction Confirm-LabExecution { param([string]`$n) }"

# DNS du DC pour resoudre corp.local (jonction)
Get-NetAdapter | Where-Object Status -eq 'Up' | Set-DnsClientServerAddress -ServerAddresses 10.10.10.10 -ErrorAction SilentlyContinue

# Attendre que le DC (DNS/AD) reponde
$deadline = (Get-Date).AddMinutes(30)
do {
  Start-Sleep -Seconds 30
  $ok = Test-Connection -ComputerName 'corp.local' -Count 1 -Quiet -ErrorAction SilentlyContinue
} until ($ok -or (Get-Date) -gt $deadline)

# Jonction au domaine (compte Administrateur du domaine = admin local post-promo)
$cred = New-Object System.Management.Automation.PSCredential("corp.local\$DomainJoinUsername", (ConvertTo-SecureString $DomainPassword -AsPlainText -Force))
# Tache de reprise post-redemarrage : audit avance + Sysmon
$resume = @'
Set-Location C:\GC210
try { .\00-Prerequis.ps1 -Task AuditSysmon }
finally { Unregister-ScheduledTask -TaskName GC210-Resume -Confirm:$false -ErrorAction SilentlyContinue }
'@
$resume | Out-File "$dir\resume.ps1" -Encoding utf8
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -File C:\GC210\resume.ps1'
Register-ScheduledTask -TaskName GC210-Resume -Action $act -Trigger (New-ScheduledTaskTrigger -AtStartup) `
  -RunLevel Highest -User SYSTEM -Force | Out-Null

Add-Computer -DomainName 'corp.local' -Credential $cred -Restart -Force
