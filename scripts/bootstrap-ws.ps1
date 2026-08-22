<#
    GC210 - Amorcage WS01 (Custom Script Extension)
      - Télécharge et installe Sysmon avec une configuration de sécurité
      -  Attend le DC puis joint corp.local (poste foothold). Laboratoire ISOLE.
#>
param(
  [Parameter(Mandatory)][string]$ScriptsBaseUrl,
  [Parameter(Mandatory)][string]$DomainPassword
)
$ErrorActionPreference = 'Stop'

# --- 1. INSTALLATION DE SYSMON ---
Write-Output "Installation de Sysmon..."
$SysmonFolder = "C:\Tools\Sysmon"
if (-not (Test-Path $SysmonFolder)) { New-Item -ItemType Directory -Path $SysmonFolder | Out-Null }

# Téléchargement des outils Sysinternals et d'une configuration de base (ex: SwiftOnSecurity ou similaire si disponible)
Invoke-WebRequest -UseBasicParsing -Uri "$ScriptsBaseUrl/Sysmon64.exe" -OutFile (Join-Path $SysmonFolder "Sysmon64.exe")
Invoke-WebRequest -UseBasicParsing -Uri "$ScriptsBaseUrl/sysmonconfig.xml" -OutFile (Join-Path $SysmonFolder "sysmonconfig.xml")

# Le binaire est telecharge tel quel (pas d'archive) : aucune extraction requise.

# Installation du service Sysmon64 (Windows 11 utilise l'architecture 64-bit nativement)
#Write-Output "Installation du service Sysmon..."
#& "$SysmonFolder\Sysmon64.exe" -accepteula -i "$SysmonFolder\sysmonconfig.xml"

# --- 2. JOINDRE LA MACHINE AU DOMAIN ---

# Valider la connectivité vers le DC
$deadline = (Get-Date).AddMinutes(30)
do {
  Start-Sleep -Seconds 30
  $ok = Test-Connection -ComputerName 'corp.local' -Count 1 -Quiet -ErrorAction SilentlyContinue
} until ($ok -or (Get-Date) -gt $deadline)

# Recuperation des credentials
$cred = New-Object System.Management.Automation.PSCredential(
  'CORP\Administrateur', (ConvertTo-SecureString $DomainPassword -AsPlainText -Force))

# Joindre la machine au domaine
Add-Computer -DomainName 'corp.local' -Credential $cred -Restart -Force