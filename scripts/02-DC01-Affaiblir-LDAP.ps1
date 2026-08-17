<#
    GC210 - Devoir 01 - Script 02 (a executer sur DC01)
    ----------------------------------------------------------------------
    Affaiblit DC01 pour rendre le relais NTLM -> LDAP fonctionnel :
      - signature LDAP non requise (LDAPServerIntegrity = 1)
      - channel binding LDAP desactive (LdapEnforceChannelBinding = 0)
    ATTENTION : reduit volontairement la securite. Laboratoire isole uniquement.
    Un redemarrage (ou redemarrage du service NTDS) est requis pour prise en compte.

    Rappel : si une GPO impose la signature LDAP ("Domain controller: LDAP server
    signing requirements"), la mettre a "None" en complement de ces cles.
#>

#Requires -RunAsAdministrator
. "$PSScriptRoot\Lab-Config.ps1"
Confirm-LabExecution "02 - Affaiblissement LDAP (DC01)"

$ntds = 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters'

# 1 = signature non requise (2 = requise)
Set-ItemProperty -Path $ntds -Name 'LDAPServerIntegrity' -Value 1 -Type DWord
Write-Host "[+ ] LDAPServerIntegrity = 1 (signature LDAP non requise)" -ForegroundColor Green

# 0 = channel binding non applique (2 = applique)
New-ItemProperty -Path $ntds -Name 'LdapEnforceChannelBinding' -Value 0 -PropertyType DWord -Force | Out-Null
Write-Host "[+ ] LdapEnforceChannelBinding = 0 (channel binding desactive)" -ForegroundColor Green

Write-Host "`n[OK] LDAP volontairement affaibli sur DC01." -ForegroundColor Cyan
Write-Host "     REDEMARRER DC01 (ou le service NTDS) pour appliquer." -ForegroundColor Yellow
Write-Host "     Verification post-redemarrage : 99-Verifier.ps1" -ForegroundColor Cyan
