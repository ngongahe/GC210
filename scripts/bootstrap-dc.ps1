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
  'Lab-Config.ps1'            = 'bf28b637698b8de434eb8ccea0314aeec94b781c9eb1407c379224cf1f1e5c71'
  '01-DC01-Comptes-AD.ps1'    = '63f6cf34361abae1498cd999567074cf888dc2152a1ea78f8dd776e3cf20cdfa'
  '02-DC01-Affaiblir-LDAP.ps1' = '2056b9dfb516a320d5c5739179cefb368f040b8274bcaf7859733e19f3f81cf3'
  '00-Prerequis.ps1'          = 'ce3009f6d3ca6c600e5add26bb0e51a4a3545b431acc2dcbdeab18ef2ba9a48a'
  'Sysmon64.exe'              = 'a60aa845457406383277afdead35bd90c7804572b99901d239cc974841df2528'
  'sysmonconfig.xml'          = '60b7b3950bd63b93ad8f6f275dce4bb932b09be16805d9dbf6cc34954a8699f2'
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