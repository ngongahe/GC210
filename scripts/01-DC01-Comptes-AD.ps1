<#
    GC210 - Devoir 01 - Script 01 (a executer sur DC01)
    ----------------------------------------------------------------------
    Cree les comptes fictifs et introduit les faiblesses cote annuaire :
      - compte a mot de passe faible (spraying)
      - compte sans pre-authentification (AS-REP roasting)
      - compte de service Web : SPN + delegation contrainte (transition de protocole)
      - compte adm_files : droit de replication (DCSync), NON Domain Admin
      - da_admin : membre de Domain Admins (cible d'usurpation S4U)
      - MachineAccountQuota laisse a 10 (RBCD)
    Prerequis : module ActiveDirectory (RSAT-AD-PowerShell), droits Admin du domaine.
#>

#Requires -RunAsAdministrator
. "$PSScriptRoot\Lab-Config.ps1"
Confirm-LabExecution "01 - Comptes AD et faiblesses (DC01)"

Import-Module ActiveDirectory -ErrorAction Stop
$domainDN = (Get-ADDomain).DistinguishedName

# --- 1. Creation des comptes ----------------------------------------------
foreach ($a in $Accounts) {
    if (Get-ADUser -Filter "SamAccountName -eq '$($a.Sam)'" -ErrorAction SilentlyContinue) {
        Write-Host "[= ] $($a.Sam) existe deja - ignore" -ForegroundColor DarkGray
        continue
    }
    New-ADUser -SamAccountName $a.Sam -Name $a.Name -DisplayName $a.Name `
        -AccountPassword (ConvertTo-SecureString $a.Pwd -AsPlainText -Force) `
        -Enabled $true -PasswordNeverExpires $true -Description $a.Desc
    Write-Host "[+ ] Compte cree : $($a.Sam)" -ForegroundColor Green
}

# --- 2. AS-REP roasting : desactiver la pre-authentification ---------------
Set-ADAccountControl -Identity 'svc_legacy' -DoesNotRequirePreAuth $true
Write-Host "[+ ] svc_legacy : DONT_REQ_PREAUTH active (AS-REP)" -ForegroundColor Green

# --- 3. Compte de service Web : SPN + delegation contrainte ---------------
Set-ADUser -Identity 'svc_web' -ServicePrincipalNames @{Add=$WebSPN}
Set-ADAccountControl -Identity 'svc_web' -TrustedToAuthForDelegation $true
Set-ADUser -Identity 'svc_web' -Add @{ 'msDS-AllowedToDelegateTo' = @($DelegationSPN) }
Write-Host "[+ ] svc_web : SPN=$WebSPN ; delegation contrainte (protocol transition) -> $DelegationSPN" -ForegroundColor Green

# --- 4. da_admin : membre de Domain Admins --------------------------------
Add-ADGroupMember -Identity 'Domain Admins' -Members 'da_admin'
Write-Host "[+ ] da_admin ajoute a Domain Admins" -ForegroundColor Green

# --- 5. adm_files : droit de replication (DCSync), sans etre Domain Admin --
$sid = (Get-ADUser 'adm_files').SID
$acl = Get-Acl "AD:\$domainDN"
$guidGetChanges    = [GUID]'1131f6aa-9c07-11d1-f79f-00c04fc2dcd2'  # DS-Replication-Get-Changes
$guidGetChangesAll = [GUID]'1131f6ad-9c07-11d1-f79f-00c04fc2dcd2'  # DS-Replication-Get-Changes-All
foreach ($g in @($guidGetChanges, $guidGetChangesAll)) {
    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $sid, 'ExtendedRight', 'Allow', $g)
    $acl.AddAccessRule($ace)
}
Set-Acl "AD:\$domainDN" -AclObject $acl
Write-Host "[+ ] adm_files : DS-Replication-Get-Changes[-All] accorde (DCSync)" -ForegroundColor Green

# --- 6. MachineAccountQuota (RBCD) ----------------------------------------
Set-ADDomain -Identity $LabDomainDNS -Replace @{ 'ms-DS-MachineAccountQuota' = 10 }
Write-Host "[+ ] ms-DS-MachineAccountQuota = 10" -ForegroundColor Green

Write-Host "`n[OK] Comptes et faiblesses annuaire configures sur DC01." -ForegroundColor Cyan
Write-Host "     Suite : executer 02-DC01-Affaiblir-LDAP.ps1 sur DC01." -ForegroundColor Cyan
