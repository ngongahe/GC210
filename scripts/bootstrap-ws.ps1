<#
    GC210 - Amorcage WS01 (Custom Script Extension)
    Attend le DC puis joint corp.local (poste foothold). Laboratoire ISOLE.
#>
param(
  [Parameter(Mandatory)][string]$ScriptsBaseUrl,
  [Parameter(Mandatory)][string]$DomainPassword
)
$ErrorActionPreference = 'Stop'

$deadline = (Get-Date).AddMinutes(30)
do {
  Start-Sleep -Seconds 30
  $ok = Test-Connection -ComputerName 'corp.local' -Count 1 -Quiet -ErrorAction SilentlyContinue
} until ($ok -or (Get-Date) -gt $deadline)

$cred = New-Object System.Management.Automation.PSCredential(
  'CORP\Administrateur', (ConvertTo-SecureString $DomainPassword -AsPlainText -Force))

Add-Computer -DomainName 'corp.local' -Credential $cred -Restart -Force
