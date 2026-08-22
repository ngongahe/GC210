<#  GC210 - Amorcage SRV01 : DNS resolvable -> telechargement -> DNS du DC -> jonction #>
param(
  [Parameter(Mandatory)][string]$ScriptsBaseUrl,
  [Parameter(Mandatory)][string]$DomainJoinUsername,
  [Parameter(Mandatory)][string]$DomainPassword
)
$ErrorActionPreference = 'Stop'

# 1. DNS Azure le temps du telechargement (le DC n'est pas joignable comme DNS a coup sur)
Get-NetAdapter | Where-Object Status -eq 'Up' | Set-DnsClientServerAddress -ServerAddresses 168.63.129.16 -ErrorAction SilentlyContinue

$dir = 'C:\GC210'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$scriptsHost = ([System.Uri]$ScriptsBaseUrl).DnsSafeHost
$scriptsDeadline = (Get-Date).AddMinutes(10)
do {
  $scriptsDns = Resolve-DnsName -Name $scriptsHost -Type A -ErrorAction SilentlyContinue
  if (-not $scriptsDns) { Start-Sleep -Seconds 30 }
} until ($scriptsDns -or (Get-Date) -gt $scriptsDeadline)
if (-not $scriptsDns) { throw "Le nom $scriptsHost n'est pas resolvable dans le delai imparti." }

$expectedHashes = @{
  'Lab-Config.ps1'               = 'a0d31f76869473416d5c979f45ce8c34ad8d776815d06505128c136b1cde1f8e'
  '03-SRV01-Web-Fichiers.ps1'    = '30e6b7e126b4eb40533e09426518c4a2b737086a1d69fbe024c1f35bf6535011'
  '00-Prerequis.ps1'             = '20716da8630482f469dec0c48ff441559bd533ec684ac64bcb896bb8881e36ad'
  'Sysmon64.exe'                 = 'a60aa845457406383277afdead35bd90c7804572b99901d239cc974841df2528'
  'sysmonconfig.xml'             = 'cf4012a6f8bfd6ac7c3780650171298534f7e228c8517791058baa5d7bdf3b66'
}
foreach ($f in 'Lab-Config.ps1','03-SRV01-Web-Fichiers.ps1','00-Prerequis.ps1','Sysmon64.exe','sysmonconfig.xml') {
  $destination = "$dir\$f"
  Invoke-WebRequest -UseBasicParsing "$ScriptsBaseUrl/$f" -OutFile $destination
  $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
  if ($actualHash -ne $expectedHashes[$f]) { throw "Hash SHA-256 invalide pour $f." }
}
Add-Content "$dir\Lab-Config.ps1" "`nfunction Confirm-LabExecution { param([string]`$n) }"

# 2. Basculer sur le DC pour resoudre corp.local (jonction)
Get-NetAdapter | Where-Object Status -eq 'Up' | Set-DnsClientServerAddress -ServerAddresses 10.10.10.10 -ErrorAction SilentlyContinue

# 3. Attendre le DC
$deadline = (Get-Date).AddMinutes(30)
do { Start-Sleep 30; $ok = Test-Connection -ComputerName 'corp.local' -Count 1 -Quiet -ErrorAction SilentlyContinue } until ($ok -or (Get-Date) -gt $deadline)

# 4. Tache de reprise post-redemarrage : script 03 + audit Sysmon
$resume = @'
Set-Location C:\GC210
try { .\03-SRV01-Web-Fichiers.ps1; .\00-Prerequis.ps1 -Task AuditSysmon }
finally { Unregister-ScheduledTask -TaskName GC210-Resume -Confirm:$false -ErrorAction SilentlyContinue }
'@
$resume | Out-File "$dir\resume.ps1" -Encoding utf8
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -File C:\GC210\resume.ps1'
Register-ScheduledTask -TaskName GC210-Resume -Action $act -Trigger (New-ScheduledTaskTrigger -AtStartup) -RunLevel Highest -User SYSTEM -Force | Out-Null

# 5. Jonction avec l'Administrateur du domaine (mot de passe fixe a l'etape A)
$cred = New-Object System.Management.Automation.PSCredential("corp.local\$DomainJoinUsername", (ConvertTo-SecureString $DomainPassword -AsPlainText -Force))
Add-Computer -DomainName 'corp.local' -Credential $cred -Restart -Force