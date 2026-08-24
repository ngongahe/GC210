<#
    GC210 - 99b-Verifier-Demo.ps1
    Valide l'enrichissement de demonstration (10-Demo-Enrichissement.ps1).
    A EXECUTER SUR DC01. N'evalue QUE les objets de demo (_GC210_Demo).
#>
$ErrorActionPreference = 'Continue'
Import-Module ActiveDirectory
Import-Module GroupPolicy

$DomainDN = 'DC=corp,DC=local'
$pass=0; $fail=0
function Check($label,[scriptblock]$test){
  try { $r = & $test } catch { $r = $false }
  if($r){ Write-Host "[PASS] $label"; $script:pass++ }
  else  { Write-Host "[FAIL] $label"; $script:fail++ }
}
function Info($label,[scriptblock]$val){
  try { $v = & $val } catch { $v = 'erreur' }
  Write-Host "[INFO] $label : $v"
}

# --- OU ---
Check "_GC210_Demo present"      { [bool](Get-ADOrganizationalUnit -Filter "Name -eq '_GC210_Demo'" -EA SilentlyContinue) }
Check "_GC210_Scenario present"  { [bool](Get-ADOrganizationalUnit -Filter "Name -eq '_GC210_Scenario'" -EA SilentlyContinue) }
$demoDN = (Get-ADOrganizationalUnit -Filter "Name -eq '_GC210_Demo'" -EA SilentlyContinue).DistinguishedName
foreach($o in 'Departments','ServiceAccounts','Workstations'){
  Check "OU $o" { [bool](Get-ADOrganizationalUnit -Filter "Name -eq '$o'" -SearchBase $demoDN -EA SilentlyContinue) }
}

# --- Utilisateurs ---
if($demoDN){
  $nbUsers = (Get-ADUser -Filter * -SearchBase $demoDN).Count
  Info "Utilisateurs sous _GC210_Demo" { $nbUsers }
  Check "Au moins 50 comptes (users+svc+helpdesk)" { $nbUsers -ge 50 }
  Check "Secret dans description (>=3)" { (Get-ADUser -Filter * -SearchBase $demoDN -Properties Description | Where-Object { $_.Description -match 'MDP temporaire' }).Count -ge 3 }
  Check "AS-REP (DoesNotRequirePreAuth) >=2" { (Get-ADUser -Filter 'DoesNotRequirePreAuth -eq $true' -SearchBase $demoDN).Count -ge 2 }
}

# --- Comptes de service + SPN + gMSA ---
Check "svcd_sql avec SPN"   { [bool]((Get-ADUser svcd_sql -Properties servicePrincipalName -EA SilentlyContinue).servicePrincipalName) }
Check "svcd_web avec SPN"   { [bool]((Get-ADUser svcd_web -Properties servicePrincipalName -EA SilentlyContinue).servicePrincipalName) }
Check "svcd_files avec SPN" { [bool]((Get-ADUser svcd_files -Properties servicePrincipalName -EA SilentlyContinue).servicePrincipalName) }
Check "gMSA gmsa_demo present" { [bool](Get-ADServiceAccount -Filter "Name -eq 'gmsa_demo'" -EA SilentlyContinue) }
Check "gMSA lecture par Domain Users (trop large)" {
  $g = Get-ADServiceAccount gmsa_demo -Properties PrincipalsAllowedToRetrieveManagedPassword -EA SilentlyContinue
  ($g.PrincipalsAllowedToRetrieveManagedPassword -join ';') -match 'Domain Users'
}

# --- Groupes + imbrication + helpdesk ---
$grpCount = (Get-ADGroup -Filter "Name -like 'GG_*'" -SearchBase $demoDN).Count
Info "Groupes GG_* sous _GC210_Demo" { $grpCount }
Check "Chaine N1 -> Admins" { (Get-ADGroupMember 'GG_Helpdesk_Admins' | Where-Object Name -eq 'GG_Helpdesk_N1').Count -ge 1 }
Check "Chaine Admins -> Managers" { (Get-ADGroupMember 'GG_Helpdesk_Managers' | Where-Object Name -eq 'GG_Helpdesk_Admins').Count -ge 1 }
Check "helpdesk membre de GG_Helpdesk_N1" { (Get-ADGroupMember 'GG_Helpdesk_N1' | Where-Object Name -eq 'helpdesk').Count -ge 1 }

# --- Ordinateurs + WS02 ---
Check "15 ordinateurs fictifs WK-DEMO-*" { (Get-ADComputer -Filter "Name -like 'WK-DEMO-*'").Count -ge 15 }
Check "WS02 dans _GC210_Demo\Workstations" {
  $c = Get-ADComputer -Filter "Name -eq 'WS02'" -EA SilentlyContinue
  $c -and $c.DistinguishedName -like "*OU=Workstations,OU=_GC210_Demo*"
}

# --- ACL abusable ---
Check "GenericAll GG_Helpdesk_Admins sur OU Departments" {
  $dep = (Get-ADOrganizationalUnit -Filter "Name -eq 'Departments'" -SearchBase $demoDN).DistinguishedName
  $sid = (Get-ADGroup 'GG_Helpdesk_Admins').SID.Value
  (Get-Acl "AD:\$dep").Access | Where-Object { $_.IdentityReference -match 'GG_Helpdesk_Admins' -or $_.IdentityReference.Value -eq $sid } |
    Where-Object { $_.ActiveDirectoryRights -match 'GenericAll' } | Measure-Object | ForEach-Object { $_.Count -ge 1 }
}

# --- GPO ---
foreach($g in 'Demo-FirewallOff','Demo-LogonScript','Demo-GPPSecret','Demo-HelpdeskLocalAdmin'){
  Check "GPO $g presente" { [bool](Get-GPO -Name $g -EA SilentlyContinue) }
}
# cpassword dans SYSVOL
Check "cpassword present dans SYSVOL (Demo-GPPSecret)" {
  $id = (Get-GPO -Name 'Demo-GPPSecret' -EA SilentlyContinue).Id
  if(-not $id){ return $false }
  $p = "$env:SystemRoot\SYSVOL\sysvol\corp.local\Policies\{$id}\Machine\Preferences\Groups\Groups.xml"
  (Test-Path $p) -and ((Get-Content $p -Raw) -match 'cpassword=')
}

Write-Host ""
Write-Host ("Resultat demo : {0} PASS / {1} FAIL" -f $pass,$fail)