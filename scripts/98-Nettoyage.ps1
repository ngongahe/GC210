<#
    GC210 - Devoir 01 - Script 98 : nettoyage / reinitialisation
    ----------------------------------------------------------------------
    Retire les artefacts installes par 01/02/03 pour repartir d'un etat propre.
    Execute par perimetre (-Scope) selon la machine :
      DC  : sur DC01  (comptes, ACL DCSync, restauration signature LDAP)
      SRV : sur SRV01 (partages, web.config, tache, admin local, signature SMB)

    Remarque : pour une remise a zero complete et garantie, preferer la
    restauration d'un instantane (snapshot) de VM. Ce script retire les
    faiblesses mais ne desinstalle pas les roles (IIS, AD DS).

    Exemples :
      .\98-Nettoyage.ps1 -Scope DC     # sur DC01
      .\98-Nettoyage.ps1 -Scope SRV    # sur SRV01
#>

#Requires -RunAsAdministrator
param(
    [Parameter(Mandatory)]
    [ValidateSet('DC','SRV')]
    [string]$Scope
)

. "$PSScriptRoot\Lab-Config.ps1"
Confirm-LabExecution "98 - Nettoyage ($Scope)"

if ($Scope -eq 'DC') {
    Import-Module ActiveDirectory -ErrorAction Stop
    $domainDN = (Get-ADDomain).DistinguishedName

    # --- 1. Retrait des ACE de replication (DCSync) pour adm_files ---------
    try {
        $sid = (Get-ADUser 'adm_files').SID
        $acl = Get-Acl "AD:\$domainDN"
        foreach ($g in @([GUID]'1131f6aa-9c07-11d1-f79f-00c04fc2dcd2',
                          [GUID]'1131f6ad-9c07-11d1-f79f-00c04fc2dcd2')) {
            $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                $sid, 'ExtendedRight', 'Allow', $g)
            [void]$acl.RemoveAccessRule($ace)
        }
        Set-Acl "AD:\$domainDN" -AclObject $acl
        Write-Host "[+] ACE DCSync retirees pour adm_files" -ForegroundColor Green
    } catch { Write-Host "[= ] ACE DCSync deja absentes ou compte inexistant" -ForegroundColor DarkGray }

    # --- 2. Suppression des comptes fictifs -------------------------------
    foreach ($a in $Accounts) {
        $u = Get-ADUser -Filter "SamAccountName -eq '$($a.Sam)'" -ErrorAction SilentlyContinue
        if ($u) { Remove-ADUser -Identity $u -Confirm:$false; Write-Host "[- ] Compte supprime : $($a.Sam)" -ForegroundColor Yellow }
    }

    # --- 3. Restauration de la signature / channel binding LDAP -----------
    $ntds = 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters'
    Set-ItemProperty -Path $ntds -Name 'LDAPServerIntegrity' -Value 2 -Type DWord
    New-ItemProperty  -Path $ntds -Name 'LdapEnforceChannelBinding' -Value 2 -PropertyType DWord -Force | Out-Null
    Write-Host "[+] Signature LDAP requise + channel binding restaures (redemarrer DC01)" -ForegroundColor Green
}

if ($Scope -eq 'SRV') {
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # --- 1. Tache planifiee (session adm_files) ---------------------------
    Unregister-ScheduledTask -TaskName 'GC210-AdmSession' -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "[- ] Tache GC210-AdmSession supprimee" -ForegroundColor Yellow

    # --- 2. Partages + contenu (web.config plante) ------------------------
    foreach ($n in 'Public','WebBackup') {
        if (Get-SmbShare -Name $n -ErrorAction SilentlyContinue) { Remove-SmbShare -Name $n -Force }
    }
    Remove-Item 'C:\Shares' -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[- ] Partages et web.config plante supprimes" -ForegroundColor Yellow

    # --- 3. Pool applicatif + admin local svc_web -------------------------
    if (Test-Path 'IIS:\AppPools\GC210App') { Remove-WebAppPool -Name 'GC210App' }
    try { Remove-LocalGroupMember -Group 'Administrators' -Member "$LabDomainNB\svc_web" -ErrorAction Stop
          Write-Host "[- ] svc_web retire des administrateurs locaux" -ForegroundColor Yellow } catch {}

    # --- 4. Restauration de la signature SMB ------------------------------
    Set-SmbServerConfiguration -RequireSecuritySignature $true -EnableSecuritySignature $true -Confirm:$false
    Write-Host "[+] Signature SMB requise restauree" -ForegroundColor Green
}

Write-Host "`n[OK] Nettoyage ($Scope) termine." -ForegroundColor Cyan
