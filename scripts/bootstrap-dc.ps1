<#
    GC210 - Amorcage DC01 (execute par la Custom Script Extension)
    Promotion non interactive de corp.local, puis reprise post-redemarrage
    pour executer les scripts DE01 (01, 02, audit). Laboratoire ISOLE.
#>
param(
  [Parameter(Mandatory)][string]$ScriptsBaseUrl,
  [string]$DsrmPassword
)
$ErrorActionPreference = 'Stop'

# 0. S'assurer d'un DNS resolvable pour telecharger (le DC n'est pas encore serveur DNS)
Get-NetAdapter | Where-Object Status -eq 'Up' | Set-DnsClientServerAddress -ServerAddresses 168.63.129.16 -ErrorAction SilentlyContinue

$dir = 'C:\GC210'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# 1. Telecharger les scripts DE01
$expectedHashes = @{
  'Lab-Config.ps1'             = 'a0d31f76869473416d5c979f45ce8c34ad8d776815d06505128c136b1cde1f8e'
  '01-DC01-Comptes-AD.ps1'     = '61775c2cc49b6d51f24cef9a89a7364a6f05a6f88161d476c6ed73b14abdc051'
  '02-DC01-Affaiblir-LDAP.ps1' = '54529fa7c8e713ae305b5535dd1a2206a0cb8a45008cde6eae6a85bc9422eaa7'
  '00-Prerequis.ps1'            = '20716da8630482f469dec0c48ff441559bd533ec684ac64bcb896bb8881e36ad'
  'Sysmon64.exe'              = 'a60aa845457406383277afdead35bd90c7804572b99901d239cc974841df2528'
  'sysmonconfig.xml'           = 'cf4012a6f8bfd6ac7c3780650171298534f7e228c8517791058baa5d7bdf3b66'
}
foreach ($f in 'Lab-Config.ps1','01-DC01-Comptes-AD.ps1','02-DC01-Affaiblir-LDAP.ps1','00-Prerequis.ps1', 'Sysmon64.exe', 'sysmonconfig.xml') {
  $destination = "$dir\$f"
  Invoke-WebRequest -UseBasicParsing "$ScriptsBaseUrl/$f" -OutFile $destination
  $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
  if ($actualHash -ne $expectedHashes[$f]) { throw "Hash SHA-256 invalide pour $f." }
}
# Neutraliser le garde-fou interactif (automatisation)
Add-Content "$dir\Lab-Config.ps1" "`nfunction Confirm-LabExecution { param([string]`$n) }"

# Une mise a jour de l'extension peut relancer ce script sur un DC deja promu.
$adDomain = $null
try {
  Import-Module ActiveDirectory -ErrorAction Stop
  $adDomain = Get-ADDomain -ErrorAction Stop
} catch {}
if ($adDomain -and $adDomain.DNSRoot -ieq 'corp.local') {
  Write-Output 'DC01 est deja promu; aucune nouvelle promotion ne sera lancee.'
  exit 0
}

# 2. Promotion de la foret (non interactive, sans redemarrage immediat)
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
Import-Module ADDSDeployment
# Mot de passe DSRM : fourni en argument, sinon genere aleatoirement.
# (non versionne ; le DSRM n'est pas utilise dans ce laboratoire jetable)
if ([string]::IsNullOrWhiteSpace($DsrmPassword)) {
  $rngBytes = New-Object 'System.Byte[]' 18
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($rngBytes)
  $DsrmPassword = [Convert]::ToBase64String($rngBytes) + 'Aa1!'
}
$dsrm = ConvertTo-SecureString $DsrmPassword -AsPlainText -Force
Install-ADDSForest -DomainName 'corp.local' -DomainNetbiosName 'CORP' `
  -InstallDns -SafeModeAdministratorPassword $dsrm -Force -NoRebootOnCompletion

# 3. Tache de reprise apres redemarrage : redirecteur DNS + faiblesses annuaire
$resume = @'
Set-Location C:\GC210
try {
  # Redirecteur DNS : permet au DC (et aux membres via le DC) de resoudre l'externe
  Add-DnsServerForwarder -IPAddress 168.63.129.16 -ErrorAction SilentlyContinue
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