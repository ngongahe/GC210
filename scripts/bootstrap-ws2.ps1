<#  GC210 - Amorcage WS02 (poste de DEMO du cours) : DNS du DC -> jonction
    Independant du lab du Devoir. Deploye uniquement si deploy_ws2 = true.
    NOTE : le script lui-meme est telecharge par l'extension (via DNS Azure) ;
    ici on bascule sur le DC pour resoudre corp.local, puis on joint le domaine. #>
param(
  [Parameter(Mandatory)][string]$ScriptsBaseUrl,
  [Parameter(Mandatory)][string]$DomainJoinUsername,
  [Parameter(Mandatory)][string]$DomainPassword
)
$ErrorActionPreference = 'Stop'

# DNS du DC pour resoudre corp.local
Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
  Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses 10.10.10.10 -ErrorAction SilentlyContinue
}

# Attendre la disponibilite du domaine (max 30 min)
$deadline = (Get-Date).AddMinutes(30)
do {
  Start-Sleep 30
  $ok = Test-Connection -ComputerName 'corp.local' -Count 1 -Quiet -ErrorAction SilentlyContinue
} until ($ok -or (Get-Date) -gt $deadline)

# Jonction au domaine (compte azadmin, admin du domaine)
$cred = New-Object System.Management.Automation.PSCredential(
  "corp.local\$DomainJoinUsername",
  (ConvertTo-SecureString $DomainPassword -AsPlainText -Force)
)
Add-Computer -DomainName 'corp.local' -Credential $cred -Restart -Force