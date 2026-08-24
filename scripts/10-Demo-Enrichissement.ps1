<#
    GC210 - 10-Demo-Enrichissement.ps1
    Enrichit corp.local pour les DEMONSTRATIONS du cours (partie 1 - offensive).
    Deterministe (graine 210), idempotent, non destructeur, isole sous _GC210_Demo.

    A EXECUTER SUR DC01 (via az vm run-command, methode fichier @).
    Prerequis : WS02 deploye et joint (deploy_ws2=true) pour les effets reels.

    Objets : 50 users, 15 groupes, 15 ordinateurs fictifs, 5 comptes de service (+gMSA),
             chaine de groupes imbriques, ACL abusable (GenericAll), 4 GPO (dont cpassword,
             firewall off, helpdesk local admin), compte helpdesk (PtH).

    Suivi (autres machines, hors de ce script) :
      - SRV01 : ajout helpdesk en admin local (run-command sur SRV01)
      - WS02  : gpupdate /force (run-command sur WS02) pour materialiser les GPO
#>
param([switch]$WhatIfDemo)

$ErrorActionPreference = 'Stop'
$seed = 210
$null = Get-Random -SetSeed $seed
Import-Module ActiveDirectory
Import-Module GroupPolicy

$Domain    = 'corp.local'
$DomainDN  = 'DC=corp,DC=local'
$SprayPwd  = 'Hiver2026!'                       # cohorte password spraying
$HelpdeskPwd = 'P@ssword1!'                 # helpdesk (PtH) : conforme, SANS fragment de nom, crackable rockyou+regles
$GppPlain  = 'Wintel-Demo_Local2026'            # secret expose via GPP cpassword

function Log($s,$m){ Write-Host ("[{0}] {1}" -f $s,$m) }

function Ensure-OU($name,$path){
  $dn = "OU=$name,$path"
  if (Get-ADOrganizationalUnit -Filter "distinguishedName -eq '$dn'" -EA SilentlyContinue) { Log '=' "OU existe : $dn" }
  else { New-ADOrganizationalUnit -Name $name -Path $path -ProtectedFromAccidentalDeletion $false; Log '+' "OU creee : $dn" }
  return $dn
}

# ============================================================
# 1. Arborescence d'OU
# ============================================================
$demo   = Ensure-OU '_GC210_Demo'  $DomainDN
$scen   = Ensure-OU '_GC210_Scenario' $DomainDN
$depts  = Ensure-OU 'Departments'  $demo
$ouIT   = Ensure-OU 'IT'           $depts
$ouFin  = Ensure-OU 'Finance'      $depts
$ouRH   = Ensure-OU 'RH'           $depts
$ouDir  = Ensure-OU 'Direction'    $depts
$ouSvc  = Ensure-OU 'ServiceAccounts' $demo
$ouWks  = Ensure-OU 'Workstations' $demo
$deptOUs = @($ouIT,$ouFin,$ouRH,$ouDir)

# ============================================================
# 2. Regrouper les 6 comptes du Devoir dans _GC210_Scenario
#    (deplacement uniquement s'ils sont encore dans CN=Users)
# ============================================================
foreach($s in 'e.roy','p.gagnon','svc_legacy','svc_web','adm_files','da_admin'){
  $u = Get-ADUser -Filter "SamAccountName -eq '$s'" -EA SilentlyContinue
  if($u -and $u.DistinguishedName -notlike "*$scen"){
    Move-ADObject -Identity $u.DistinguishedName -TargetPath $scen
    Log '+' "Deplace vers _GC210_Scenario : $s"
  } elseif($u){ Log '=' "Deja dans _GC210_Scenario : $s" }
}

# ============================================================
# 3. Utilisateurs de demo (50), deterministes
# ============================================================
$fn = 'marc','julie','simon','nadia','david','sophie','eric','chloe','yanik','maude','olivier','emma','hugo','laurie','felix','anne','louis','sarah','samuel','elodie','xavier','camille','antoine','maya','philippe'
$ln = 'tremblay','gagnon','roy','cote','bouchard','gauthier','morin','lavoie','fortin','gagne','ouellet','pelletier','belanger','levesque','bergeron','girard','simard','boucher','caron','beaulieu','cloutier','dube','poirier','fournier','lapointe'
$titles = 'Analyste','Technicien','Gestionnaire','Adjoint','Conseiller','Coordonnateur','Specialiste','Agent'
$deptNames = 'IT','Finance','RH','Direction'

for($i=0;$i -lt 50;$i++){
  $f = $fn[$i % $fn.Count]; $l = $ln[($i*7+3) % $ln.Count]
  $sam = ("{0}.{1}" -f $f,$l).ToLower()
  if(Get-ADUser -Filter "SamAccountName -eq '$sam'" -EA SilentlyContinue){ $sam = "$sam$i" }
  if(Get-ADUser -Filter "SamAccountName -eq '$sam'" -EA SilentlyContinue){ Log '=' "User existe : $sam"; continue }

  $di = $i % 4; $dept = $deptNames[$di]; $ouTarget = $deptOUs[$di]
  $title = $titles[$i % $titles.Count]
  $desc  = "$title, $dept"
  $pwd   = "Aut0mne+$i!Qc"          # fort par defaut (bruit)

  if($i -lt 3){                      # 3 secrets exposes dans description (T1552)
    $leak = "Zeph!r$($i)Cascade2026"
    $desc = "$title $dept - MDP temporaire (a changer): $leak"
    $pwd  = $leak                    # le secret DECRIT est le vrai mot de passe
  } elseif($i -ge 3 -and $i -lt 21){ # 18 users : cohorte spraying (T1110.003)
    $pwd = $SprayPwd
  }

  New-ADUser -SamAccountName $sam -Name "$f $l" -GivenName $f -Surname $l `
    -DisplayName "$f $l" -Department $dept -Title $title -Description $desc `
    -AccountPassword (ConvertTo-SecureString $pwd -AsPlainText -Force) `
    -Enabled $true -PasswordNeverExpires $true -Path $ouTarget
  Log '+' "User cree : $sam ($dept)"

  if($i -eq 21 -or $i -eq 22){       # 2 users AS-REP (T1558.004)
    Set-ADAccountControl -Identity $sam -DoesNotRequirePreAuth $true
    Log '+' "AS-REP active : $sam"
  }
}

# ============================================================
# 4. Comptes de service + gMSA
# ============================================================
function New-SvcUser($sam,$spn,$pwd,$asrep){
  if(Get-ADUser -Filter "SamAccountName -eq '$sam'" -EA SilentlyContinue){ Log '=' "Svc existe : $sam"; return }
  New-ADUser -SamAccountName $sam -Name $sam -DisplayName $sam `
    -AccountPassword (ConvertTo-SecureString $pwd -AsPlainText -Force) `
    -Enabled $true -PasswordNeverExpires $true -Path $ouSvc `
    -Description "Compte de service (demo)"
  if($spn){ Set-ADUser -Identity $sam -ServicePrincipalNames @{Add=$spn} ; Log '+' "SPN pose sur $sam : $spn" }
  if($asrep){ Set-ADAccountControl -Identity $sam -DoesNotRequirePreAuth $true ; Log '+' "AS-REP active : $sam" }
  Log '+' "Svc cree : $sam"
}
New-SvcUser 'svcd_sql'    'MSSQLSvc/sql.corp.local:1433' 'Ete2025'            $false   # kerberoast craquable
New-SvcUser 'svcd_web'    'HTTP/webapp.corp.local'       'Portail#2023'       $false   # kerberoast moyen
New-SvcUser 'svcd_files'  'CIFS/files.corp.local'        'r$K8w!Qz2pLmVx7@nT' $false   # kerberoast non craquable (temoin)
New-SvcUser 'svcd_old'    $null                          'Soleil2024'         $true    # AS-REP

# gMSA a lecture trop large (moderne, T1552)
try {
  if(-not (Get-KdsRootKey -EA SilentlyContinue)){ Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10)) | Out-Null; Log '+' "Cle racine KDS creee (retrodatee)" }
  if(-not (Get-ADServiceAccount -Filter "Name -eq 'gmsa_demo'" -EA SilentlyContinue)){
    New-ADServiceAccount -Name 'gmsa_demo' -DNSHostName 'gmsa_demo.corp.local' `
      -PrincipalsAllowedToRetrieveManagedPassword 'Domain Users' -Enabled $true -Path $ouSvc
    Log '+' "gMSA cree : gmsa_demo$ (lecture par Domain Users = trop large)"
  } else { Log '=' "gMSA existe : gmsa_demo$" }
} catch { Log '!' "gMSA : $($_.Exception.Message)" }

# ============================================================
# 5. Groupes (15) + chaine imbriquee + helpdesk (PtH)
# ============================================================
$groups = 'GG_Helpdesk_N1','GG_Helpdesk_Admins','GG_Helpdesk_Managers',
          'GG_IT_Users','GG_Finance_Users','GG_RH_Users','GG_Direction_Users','GG_All_Staff',
          'GG_VPN_Users','GG_FileShare_RW','GG_Printer_Admins','GG_App_SAP',
          'GG_Remote_Desktop','GG_Wiki_Editors','GG_Backup_Operators_Demo'
foreach($g in $groups){
  if(Get-ADGroup -Filter "Name -eq '$g'" -EA SilentlyContinue){ Log '=' "Groupe existe : $g" }
  else { New-ADGroup -Name $g -GroupScope Global -GroupCategory Security -Path $demo -Description "Groupe de demo"; Log '+' "Groupe cree : $g" }
}
# Chaine imbriquee : N1 -> Admins -> Managers (BloodHound shortest path)
Add-ADGroupMember -Identity 'GG_Helpdesk_Admins'   -Members 'GG_Helpdesk_N1'      -EA SilentlyContinue
Add-ADGroupMember -Identity 'GG_Helpdesk_Managers' -Members 'GG_Helpdesk_Admins'  -EA SilentlyContinue
Log '+' "Imbrication : GG_Helpdesk_N1 -> Admins -> Managers"

# Compte helpdesk (cible PtH) : membre de N1 (herite du chemin)
if(-not (Get-ADUser -Filter "SamAccountName -eq 'helpdesk'" -EA SilentlyContinue)){
  New-ADUser -SamAccountName 'helpdesk' -Name 'Helpdesk Support' -DisplayName 'Helpdesk Support' `
    -AccountPassword (ConvertTo-SecureString $HelpdeskPwd -AsPlainText -Force) `
    -Enabled $true -PasswordNeverExpires $true -Path $ouSvc -Description "Support helpdesk (demo PtH)"
  Log '+' "Compte helpdesk cree"
} else { Log '=' "Compte helpdesk existe" }
Add-ADGroupMember -Identity 'GG_Helpdesk_N1' -Members 'helpdesk' -EA SilentlyContinue

# ============================================================
# 6. Ordinateurs fictifs (15) + deplacement de WS02
# ============================================================
for($i=1;$i -le 15;$i++){
  $c = "WK-DEMO-{0:D2}" -f $i
  if(Get-ADComputer -Filter "Name -eq '$c'" -EA SilentlyContinue){ Log '=' "Ordi existe : $c" }
  else { New-ADComputer -Name $c -SAMAccountName "$c`$" -Path $ouWks -Enabled $false -Description "Poste fictif (demo)"; Log '+' "Ordi fictif : $c" }
}
$ws2 = Get-ADComputer -Filter "Name -eq 'WS02'" -EA SilentlyContinue
if($ws2 -and $ws2.DistinguishedName -notlike "*$ouWks"){ Move-ADObject -Identity $ws2.DistinguishedName -TargetPath $ouWks; Log '+' "WS02 deplace dans _GC210_Demo\Workstations" }
elseif($ws2){ Log '=' "WS02 deja dans Workstations" } else { Log '!' "WS02 introuvable (deploy_ws2=true ?)" }

# ============================================================
# 7. ACL abusable deterministe : GenericAll de GG_Helpdesk_Admins sur OU Departments
# ============================================================
try {
  $grp = Get-ADGroup 'GG_Helpdesk_Admins'
  $sid = New-Object System.Security.Principal.SecurityIdentifier $grp.SID
  $acl = Get-Acl "AD:\$depts"
  $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid,
          [System.DirectoryServices.ActiveDirectoryRights]::GenericAll,
          [System.Security.AccessControl.AccessControlType]::Allow,
          [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
  $acl.AddAccessRule($ace)
  Set-Acl -Path "AD:\$depts" -AclObject $acl
  Log '+' "ACL : GenericAll GG_Helpdesk_Admins -> OU Departments (T1222/T1098)"
} catch { Log '!' "ACL : $($_.Exception.Message)" }

# ============================================================
# 8. GPO de demo (creation + liaison + effets reels)
# ============================================================
$sysvolGroups = '{17D89FEC-5C44-4972-B12D-241CAEF74509}{79F92669-4224-476C-9C5C-6EFB4D87DF4A}'

function Ensure-GPO($name){
  $g = Get-GPO -Name $name -EA SilentlyContinue
  if(-not $g){ $g = New-GPO -Name $name; Log '+' "GPO creee : $name" } else { Log '=' "GPO existe : $name" }
  return $g
}
function Link-GPO($name,$targetDN){
  try { New-GPLink -Name $name -Target $targetDN -EA Stop | Out-Null; Log '+' "GPO liee : $name -> $targetDN" }
  catch { Log '=' "Lien GPO deja present : $name" }
}
function New-GPPCPassword($plain){
  # AES-256-CBC, cle publiee par Microsoft (MS14-025), IV nul -> cpassword GPP
  $key = [byte[]](0x4e,0x99,0x06,0xe8,0xfc,0xb6,0x6c,0xc9,0xfa,0xf4,0x93,0x10,0x62,0x0f,0xfe,0xe8,0xf4,0x96,0xe8,0x06,0xcc,0x05,0x79,0x90,0x20,0x9b,0x09,0xa4,0x33,0xb6,0x6c,0x1b)
  $aes = [System.Security.Cryptography.Aes]::Create(); $aes.Key=$key; $aes.IV=(New-Object byte[] 16)
  $aes.Mode='CBC'; $aes.Padding='PKCS7'
  $enc = $aes.CreateEncryptor(); $b=[System.Text.Encoding]::Unicode.GetBytes($plain)
  [Convert]::ToBase64String($enc.TransformFinalBlock($b,0,$b.Length))
}
function Write-Sysvol($gpo,$rel,$content){
  $base = "$env:SystemRoot\SYSVOL\sysvol\$Domain\Policies\{$($gpo.Id)}\$rel"
  New-Item -ItemType Directory -Force -Path (Split-Path $base) | Out-Null
  Set-Content -Path $base -Value $content -Encoding UTF8
  # Enregistrer la CSE Preferences-Groups pour que la GPO soit appliquee
  $dn = "CN={$($gpo.Id)},CN=Policies,CN=System,$DomainDN"
  Set-ADObject -Identity $dn -Replace @{ 'gPCMachineExtensionNames' = "[$sysvolGroups]" } -EA SilentlyContinue
}

# 8.1 Demo-FirewallOff : desactive le pare-feu (effet reel sur WS02) - via registre GPO
$g1 = Ensure-GPO 'Demo-FirewallOff'
Set-GPRegistryValue -Name 'Demo-FirewallOff' -Key 'HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile' -ValueName 'EnableFirewall' -Type DWord -Value 0 | Out-Null
Set-GPRegistryValue -Name 'Demo-FirewallOff' -Key 'HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile' -ValueName 'EnableFirewall' -Type DWord -Value 0 | Out-Null
Link-GPO 'Demo-FirewallOff' $ouWks
Log '+' "GPO Demo-FirewallOff : pare-feu desactive (effet reel a l'application)"

# 8.2 Demo-LogonScript : illustration vecteur (registre benin), liee aux departements
$g2 = Ensure-GPO 'Demo-LogonScript'
Set-GPRegistryValue -Name 'Demo-LogonScript' -Key 'HKCU\Software\GC210' -ValueName 'DemoLogon' -Type String -Value 'demo' | Out-Null
Link-GPO 'Demo-LogonScript' $depts

# 8.3 Demo-GPPSecret : cpassword dans SYSVOL (historique, T1552.006)
$g3 = Ensure-GPO 'Demo-GPPSecret'
$cpwd = New-GPPCPassword $GppPlain
$groupsXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Groups clsid="{3125E937-EB16-4b4c-9934-544FC6D24D26}">
  <User clsid="{DF5F1855-51E5-4d24-8B1A-D9BDE98BA1D1}" name="wintel_local" image="0" changed="2026-01-01 00:00:00" uid="{$([guid]::NewGuid())}">
    <Properties action="C" fullName="Compte local demo" description="cpassword demo" cpassword="$cpwd" changeLogon="0" noChange="1" neverExpires="1" acctDisabled="0" userName="wintel_local"/>
  </User>
</Groups>
"@
Write-Sysvol $g3 'Machine\Preferences\Groups\Groups.xml' $groupsXml
Link-GPO 'Demo-GPPSecret' $ouWks
Log '+' "GPO Demo-GPPSecret : cpassword pose ($GppPlain dechiffrable)"

# 8.4 Demo-HelpdeskLocalAdmin : ajoute helpdesk aux admins locaux (Restricted Groups via GPP)
$g4 = Ensure-GPO 'Demo-HelpdeskLocalAdmin'
$hdSid = (Get-ADUser 'helpdesk').SID.Value
$adminGroupsXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Groups clsid="{3125E937-EB16-4b4c-9934-544FC6D24D26}">
  <Group clsid="{6D4A79E4-529C-4481-ABD0-F5BD7EA93BA7}" name="Administrators (built-in)" image="2" changed="2026-01-01 00:00:00" uid="{$([guid]::NewGuid())}">
    <Properties action="U" newName="" description="" deleteAllUsers="0" deleteAllGroups="0" removeAccounts="0" groupSid="S-1-5-32-544" groupName="Administrators (built-in)">
      <Members><Member name="CORP\helpdesk" action="ADD" sid="$hdSid"/></Members>
    </Properties>
  </Group>
</Groups>
"@
Write-Sysvol $g4 'Machine\Preferences\Groups\Groups.xml' $adminGroupsXml
Link-GPO 'Demo-HelpdeskLocalAdmin' $ouWks
Log '+' "GPO Demo-HelpdeskLocalAdmin : helpdesk -> admins locaux (prepare PtH)"

# ============================================================
Log '+' "Enrichissement de demonstration termine."
Log '=' "Suite : (SRV01) ajouter helpdesk admin local ; (WS02) gpupdate /force"