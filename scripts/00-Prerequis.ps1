<#
    GC210 - Devoir 01 - Script 00 : prerequis du laboratoire
    ----------------------------------------------------------------------
    Prepare l'infrastructure avant les scripts 01/02/03.
    Execute par tache (-Task) selon la machine :
      DcPromo     : sur la future DC01 (promotion de la foret corp.local)  -> redemarre
      JoinDomain  : sur SRV01 et WS01 (jonction au domaine)                -> redemarre
      AuditSysmon : sur DC01, SRV01 et WS01 (audit avance + ligne de commande 4688 + Sysmon)
    Environnement volontairement vulnerable - laboratoire ISOLE uniquement.

    Exemples :
      .\00-Prerequis.ps1 -Task DcPromo       # sur la future DC01
      .\00-Prerequis.ps1 -Task JoinDomain    # sur SRV01, puis sur WS01
      .\00-Prerequis.ps1 -Task AuditSysmon   # sur DC01, SRV01, puis sur WS01
#>

#Requires -RunAsAdministrator
param(
    [Parameter(Mandatory)]
    [ValidateSet('DcPromo','JoinDomain','AuditSysmon')]
    [string]$Task
)

. "$PSScriptRoot\Lab-Config.ps1"
Confirm-LabExecution "00 - Prerequis ($Task)"

switch ($Task) {

    'DcPromo' {
        # --- Promotion de la foret sur la future DC01 -----------------------
        # Prealable conseille : IP statique + DNS local sur cette machine.
        Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools
        Import-Module ADDSDeployment
        $dsrm = Read-Host "Mot de passe DSRM (SafeMode) - fictif" -AsSecureString
        Install-ADDSForest -DomainName $LabDomainDNS -DomainNetbiosName $LabDomainNB `
            -InstallDns -SafeModeAdministratorPassword $dsrm -Force
        Write-Host "[+] Promotion lancee : la machine va redemarrer." -ForegroundColor Green
    }

    'JoinDomain' {
        # --- Jonction de SRV01 / WS01 au domaine ----------------------------
        # Prealable : DNS de cette machine pointant vers DC01.
        $cred = Get-Credential -Message "Identifiants d'un compte autorise a joindre le domaine" `
                    -UserName "$LabDomainNB\Administrateur"
        Add-Computer -DomainName $LabDomainDNS -Credential $cred -Restart
        Write-Host "[+] Jonction demandee : la machine va redemarrer." -ForegroundColor Green
    }

    'AuditSysmon' {
        # --- 1. Audit avance (Logon, Kerberos, DS Changes, Process) ---------
        $subs = @(
            'Logon','Logoff','Special Logon','Other Logon/Logoff Events',
            'Kerberos Authentication Service','Kerberos Service Ticket Operations','Credential Validation',
            'Directory Service Changes','Directory Service Access',
            'Process Creation'
        )
        foreach ($s in $subs) {
            auditpol /set /subcategory:"$s" /success:enable /failure:enable | Out-Null
        }
        Write-Host "[+] Sous-categories d'audit avance activees" -ForegroundColor Green

        # --- 2. Ligne de commande dans l'Event 4688 -------------------------
        $auditKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
        if (-not (Test-Path $auditKey)) { New-Item -Path $auditKey -Force | Out-Null }
        New-ItemProperty -Path $auditKey -Name 'ProcessCreationIncludeCmdLine_Enabled' `
            -Value 1 -PropertyType DWord -Force | Out-Null
        Write-Host "[+] Ligne de commande incluse dans 4688" -ForegroundColor Green

        # --- 3. Sysmon (si binaire + config fournis dans ce dossier) --------
        $sysmon = Join-Path $PSScriptRoot 'Sysmon64.exe'
        $cfg    = Join-Path $PSScriptRoot 'sysmonconfig.xml'
        if ((Test-Path $sysmon) -and (Test-Path $cfg)) {
            & $sysmon -accepteula -i $cfg
            Write-Host "[+] Sysmon installe avec la configuration fournie" -ForegroundColor Green
        } else {
            Write-Host "[!] Sysmon non installe : deposer 'Sysmon64.exe' et 'sysmonconfig.xml' dans ce dossier, puis relancer." -ForegroundColor Yellow
        }

        Write-Host "`n[i] Rappel : l'Event 5136 exige des SACL d'audit sur les OU/objets sensibles (a poser separement)." -ForegroundColor DarkCyan
    }
}
