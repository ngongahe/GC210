<#
    GC210 - Devoir 01 - Script 99 : verification du montage
    ----------------------------------------------------------------------
    Controle la presence des faiblesses attendues.
    Executer les tests annuaire/DC sur DC01, les tests SMB/IIS sur SRV01.
    (Le script tente chaque test et signale ceux non applicables localement.)
#>

. "$PSScriptRoot\Lab-Config.ps1"
$ok = 0; $ko = 0
function Test-Item([string]$Label, [scriptblock]$Check) {
    try {
        if (& $Check) { Write-Host "[PASS] $Label" -ForegroundColor Green; $script:ok++ }
        else          { Write-Host "[FAIL] $Label" -ForegroundColor Red;   $script:ko++ }
    } catch {
        Write-Host "[SKIP] $Label ($($_.Exception.Message))" -ForegroundColor DarkGray
    }
}

# --- Tests annuaire (DC01) -------------------------------------------------
Test-Item "svc_legacy : DONT_REQ_PREAUTH" {
    (Get-ADUser svc_legacy -Properties userAccountControl).userAccountControl -band 0x400000 }
Test-Item "svc_web : SPN HTTP present" {
    (Get-ADUser svc_web -Properties servicePrincipalName).servicePrincipalName -contains $WebSPN }
Test-Item "svc_web : delegation contrainte -> $DelegationSPN" {
    (Get-ADUser svc_web -Properties 'msDS-AllowedToDelegateTo').'msDS-AllowedToDelegateTo' -contains $DelegationSPN }
Test-Item "svc_web : TRUSTED_TO_AUTH_FOR_DELEGATION" {
    (Get-ADUser svc_web -Properties userAccountControl).userAccountControl -band 0x1000000 }
Test-Item "adm_files : NON membre de Domain Admins" {
    -not ((Get-ADGroupMember 'Domain Admins' | Select-Object -Expand SamAccountName) -contains 'adm_files') }
Test-Item "da_admin : membre de Domain Admins" {
    (Get-ADGroupMember 'Domain Admins' | Select-Object -Expand SamAccountName) -contains 'da_admin' }
Test-Item "MachineAccountQuota = 10" {
    (Get-ADObject (Get-ADDomain).DistinguishedName -Properties 'ms-DS-MachineAccountQuota').'ms-DS-MachineAccountQuota' -eq 10 }

# --- Tests DC01 (registre LDAP) -------------------------------------------
$ntds = 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters'
Test-Item "LDAPServerIntegrity = 1 (signature non requise)" {
    (Get-ItemProperty $ntds -Name LDAPServerIntegrity -ErrorAction Stop).LDAPServerIntegrity -eq 1 }
Test-Item "LdapEnforceChannelBinding = 0" {
    (Get-ItemProperty $ntds -Name LdapEnforceChannelBinding -ErrorAction Stop).LdapEnforceChannelBinding -eq 0 }

# --- Tests SRV01 (SMB / IIS / tache) --------------------------------------
Test-Item "Partage WebBackup present" { Get-SmbShare -Name WebBackup -ErrorAction Stop }
Test-Item "web.config plante contient le mot de passe svc_web" {
    (Get-Content 'C:\Shares\WebBackup\web.config' -Raw) -match 'Password=' }
Test-Item "Tache GC210-AdmSession (session adm_files)" {
    Get-ScheduledTask -TaskName 'GC210-AdmSession' -ErrorAction Stop }
Test-Item "Signature SMB non requise (SRV01)" {
    -not (Get-SmbServerConfiguration).RequireSecuritySignature }

Write-Host "`nResultat : $ok PASS / $ko FAIL" -ForegroundColor Cyan
