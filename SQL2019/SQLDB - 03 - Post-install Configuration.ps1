###############################################################################
##
## SQLDB - 03 - Post-install Configuration
##
###############################################################################

<#

.SYNOPSIS
    Encapsulates the PostBuildConfig scripts.

.DESCRIPTION
    Completes various post-installation configuration steps which bring the
	instance inline with the BoE standard build for a SQL Server instance.
	
.PARAMETER Environment
    The environment tier, DEV, UAT, PRD, that the instance is implemented
	in.

.NOTES
    Version:        0.1.7282.25140
    Author:         Brian Poore
    Creation Date:  19th June 2019
    Purpose/Change: Initial Draft

.OUTPUTS
    ResultStatus: "0 - Success, 1 - Warning, 2 - Failure"
    ErrorMessage: "Error Message caught/written during script execution ("Success" if resultstatus = "0")"
    ErrorType:    "The error type caught during script execution ("Success" if resultstatus = "0")"
    Trace:        "Script Activity Trace"

#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Environment
)

#Import-Module sqlserver -DisableNameChecking

# Define "Tracelog" function for writing to Trace (remote sessions when used
# will append an external log to this log on completion using an "Appendlog"
# function, defined in the remote session)
Function Tracelog ([string]$Message) {
    $Script:CurrentAction = $Message
    $Script:Trace += ((Get-Date).ToString() + "`t" + $Message + " `r`n")
}

Set-StrictMode -Off

# Set error Action Global Preference
[string]$ErrorActionPreference = 'Stop'
[int]$ResultStatus = 0
[string]$ErrorMessage = "Success"
[string]$ErrorType = "Success"

[string]$Trace = (get-Date).ToString() + "`t" + "INFO: Runbook Script Trace Started : " + $MyInvocation.MyCommand.Name + " `r`n"

Function GetLogonAccount {
    param(
	    [STRING] $ServiceName
    )

    if ($ServiceName -is [String]) {   
        $LogonAccount = (Get-WmiObject -class Win32_Service -Filter "Name Like '%$serviceName%'").StartName

        #replace "BOE\" with empty string
		if ($LogonAccount -ne $NULL) {
            $LogonAccount = $LogonAccount.Replace("BOE\","")
        }

        return $LogonAccount
    }
}

Function AddToLocalGroup {
    param(
	    [String] $Group,
		[String] $Member
    )

    try {
        Write-Host "Adding" $Member "to" $Group
        Add-LocalGroupMember -Group $Group -Member $Member -ErrorAction stop    
    } catch [Microsoft.PowerShell.Commands.MemberExistsException] {
        return $Member + " already in " + $Group
    }
}

Function AddServiceAccount ([String]$ServiceAccount) {
    AddToLocalGroup -Group  "Act as part of the operating system" -Member BOE\$ServiceAccount
    AddToLocalGroup -Group  "Adjust memory quotas for a process" -Member BOE\$ServiceAccount
    AddToLocalGroup -Group  "Allow log on locally" -Member BOE\$ServiceAccount
    AddToLocalGroup -Group  "Bypass traverse checking" -Member BOE\$ServiceAccount
    AddToLocalGroup -Group  "Debug Programs" -Member BOE\$ServiceAccount
    AddToLocalGroup -Group  "Enable accounts for delegation" -Member BOE\$ServiceAccount
    AddToLocalGroup -Group  "Generate security audits" -Member BOE\$ServiceAccount
    AddToLocalGroup -Group  "Impersonate a client" -Member BOE\$ServiceAccount
    AddToLocalGroup -Group  "Increase a process working set" -Member BOE\$ServiceAccount
    AddToLocalGroup -Group  "Increase scheduling priority" -Member BOE\$ServiceAccount
    AddToLocalGroup -Group  "Allow Log On Locally" -Member BOE\$ServiceAccount
    AddToLocalGroup -Group  "Perform volume maintenance tasks" -Member BOE\$ServiceAccount
    AddToLocalGroup -Group  "Replace a process level token" -Member BOE\$ServiceAccount            
}

Function changePort ($SQLName , $Instance, $port) {
    $SQLName
    $Instance

    # Load SMO Wmi.ManagedComputer assembly
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement") | Out-Null

    Trap {
        $err = $_.Exception
        while ( $err.InnerException ) {
            $err = $err.InnerException
            write-output $err.Message
        }
        continue
    }

    # Connect to the instance using SMO
    $m = New-Object ('Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer') $SQLName
    $urn = "ManagedComputer[@Name='$SQLName']/ServerInstance[@Name='$Instance']/ServerProtocol[@Name='Tcp']"
    $Tcp = $m.GetSmoObject($urn)
    $Enabled = $Tcp.IsEnabled
    #Enable TCP/IP if not enabled
	IF (!$Enabled) { $Tcp.IsEnabled = $true }

    #Set to listen on port and disable dynamic ports
	$m.GetSmoObject($urn + "/IPAddress[@Name='IPAll']").IPAddressProperties[1].Value = $port
	$m.GetSmoObject($urn + "/IPAddress[@Name='IPAll']").IPAddressProperties['TcpDynamicPorts'].Value = ''
	$TCP.alter()

    return $newport= $m.GetSmoObject($urn + "/IPAddress[@Name='IPAll']").IPAddressProperties[1].Value
}

try {
    # Add script execution start details to trace log
    Tracelog "INFO: Script executing in local PowerShell version [$($PSVersionTable.PSVersion.ToString())] session in a [$([IntPtr]::Size * 8)] bit process"
    Tracelog "INFO: Running as user [$([Environment]::UserDomainName)\$([Environment]::UserName)] on host [$($env:COMPUTERNAME)]"
    Tracelog "INFO: Input Parameters received: `r`n`t`t`t`tEnvironment=[$Environment]"

    Tracelog "INFO: Placing into SCOM Maintenance Mode for 180 minutes"
	eventcreate /so "DEV Maintenance Mode" /Id 747  /D 180 /T INFORMATION /L Application

    Tracelog "INFO: Enabling TCP and setting default port"
    changePort $env:COMPUTERNAME 'INST1' '2130'

    Tracelog "INFO: Restarting SQL Server"
    net stop 'SQLAGENT$INST1'
    net stop 'MSSQL$INST1'
    net start 'MSSQL$INST1'
    net start 'SQLAGENT$INST1'

	#$SuperSocketKey = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL13.INST1\MSSQLServer\SuperSocketNetLib' 
	$SuperSocketKey = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.INST1\MSSQLServer\SuperSocketNetLib'

	if ((Get-Item ($SuperSocketKey + "\Tcp")).GetValue('Enabled') -ne 1 -or `
	    (Get-Item ($SuperSocketKey + "\Np")).GetValue('Enabled') -ne 0 -or `
        (Get-Item ($SuperSocketKey + "\Tcp\IpAll")).GetValue('TcpPort') -ne "2130") {
			Throw "Network configuration incorrect"
	}

	TraceLog "INFO: Disable CEIP services"
    Get-Service -name "*TELEMETRY*" | Stop-Service -passthru | Set-Service -startmode disabled

	TraceLog "INFO: Deactivate CEIP registry keys"
    $RegisteryKey = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server'
    $FoundKeys = Get-ChildItem $RegisteryKey -Recurse | Where-Object -Property Property -eq 'EnableErrorReporting'

    foreach ($SqlFoundKey in $FoundKeys) {
        $SqlFoundKey | Set-ItemProperty -Name EnableErrorReporting -Value 0
        $SqlFoundKey | Set-ItemProperty -Name CustomerFeedback -Value 0
    }

	TraceLog "INFO: Deactivate WoW CEIP registry keys"
	$WowKey = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Microsoft SQL Server"
    $FoundWowKeys = Get-ChildItem $WowKey | Where-Object -Property Property -eq 'EnableErrorReporting'

    foreach ($SqlFoundWowKey in $FoundWowKeys) {
        $SqlFoundWowKey | Set-ItemProperty -Name EnableErrorReporting -Value 0
        $SqlFoundWowKey | Set-ItemProperty -Name CustomerFeedback -Value 0
    }

	if ((Get-WindowsFeature -Name Failover-Cluster).Installed) { 
        TraceLog "INFO: Remove CEIP cluster resource"
        
		try {
            Remove-ClusterResource -Name "SQL Server CEIP (INST1)" -Force		
		}
		catch {
            TraceLog "INFO: CEIP cluster resource not found"
		}
    }

	if ((Get-Service -Name "*TELEMETRY*" | Where-Object {$_.Status -ne "Stopped"}).Count -ne 0 -or `
        (Get-Service -Name "*TELEMETRY*" | Where-Object {$_.StartType -ne "Disabled"}).Count -ne 0) {
		    Throw "CEIP Service not stopped and/or disabled"
	}

	TraceLog "INFO: Updating LSA Permissions for SQL Server service account"
	$ServiceName = 'MSSQL$INST1'
    $LogonAccount = GetLogonAccount -ServiceName $ServiceName 
    AddServiceAccount $LogonAccount

	TraceLog "INFO: Updating LSA Permissions for SQL Agent service account"
	$ServiceName = 'SQLAgent$INST1'
    $LogonAccount = GetLogonAccount -ServiceName $ServiceName 
    AddServiceAccount $LogonAccount

	TraceLog "INFO: Updating LSA Permissions for FTS service account"
	$FTServAccount = "NT Service\MSSQLFDLauncher`$INST1"
    AddToLocalGroup -Group "Log on as a service" -Member $FTServAccount

	TraceLog "INFO: Set DTC settings"
    Set-DtcNetworkSetting –DtcName Local –AuthenticationLevel NoAuth –InboundTransactionsEnabled 1 –OutboundTransactionsEnabled 1 –RemoteClientAccessEnabled 1 -Confirm:$False

	TraceLog "INFO: Copy dbatools to the local modules folder and unlock files"
	$BasePath='C:\DBservices'
	robocopy /MIR /ETA $BasePath'\BuildAutomation\Modules\dbatools' 'C:\Program Files\WindowsPowerShell\Modules\dbatools'
        robocopy /MIR /ETA $BasePath'\BuildAutomation\Modules\InportExcel' 'C:\Program Files\WindowsPowerShell\Modules\ImportExcel'
	# added line below to copy SQLServer module into WindowsPowershell directory
	robocopy /MIR /ETA $BasePath'\BuildAutomation\Modules\SQLServer' 'C:\Program Files\WindowsPowerShell\Modules\SQLServer'
    Get-ChildItem -Recurse -Path $BasePath'\BuildAutomation\Modules\' | Unblock-File

<#	04/Nov/2019 Alykhan and Brian - we now have a new SCOM script. For the moment the following orig code is commented out
	TraceLog "INFO: Configuring SCCM for SQL Server Instance"
	if ($Environment -eq "DEV") {
	    TraceLog "INFO: DEV SCCM Configuration"
	    & 'C:\DBServices\RAA_BOE\BOE\SetSQLMPLowPrivPermsDEV.cmd'
        cd 'C:\program files (x86)\Microsoft SQL Server\130\Shared'
        mofcomp.exe sqlmgmproviderxpsp2up.mof
        Invoke-SqlCmd -ServerInstance ($env:COMPUTERNAME + "\INST1") -InputFile 'C:\DBServices\RAA_BOE\BOE\RAA_SCOM_SQL_DEV.txt'
	} else {
	    TraceLog "INFO: non-DEV SCCM Configuration"
	    & 'C:\DBServices\RAA_PRD\PRD\SetSQLMPLowPrivPermsPRD.cmd'
        cd 'C:\program files (x86)\Microsoft SQL Server\130\Shared'
        mofcomp.exe sqlmgmproviderxpsp2up.mof
        Invoke-SqlCmd -ServerInstance ($env:COMPUTERNAME + "\INST1") -InputFile 'C:\DBServices\RAA_PRD\PRD\RAA_SCOM_SQL_PRD.sql'

	
	}
    Invoke-SqlCmd -ServerInstance ($env:COMPUTERNAME + "\INST1") -Query "xp_readerrorlog 0, 1 , `"RAA`""
    Restart-Service HealthService 
#>
}
catch {
    $ResultStatus = '2'
    $ErrorMessage = $error[0].Exception.Message
    $ErrorType = $error[0].Exception.GetType().fullname

    Tracelog ("ERROR: Unhandled exception caught: $ErrorMessage")
}
finally {
    Tracelog "INFO: Preparing PS Object that will be returned"
    $ReturnObject = New-Object -TypeName psobject
    $ReturnObject | Add-Member -MemberType NoteProperty -Name ResultStatus -Value $Resultstatus
    $ReturnObject | Add-Member -MemberType NoteProperty -Name ErrorMessage -Value $ErrorMessage.ToString()
    $ReturnObject | Add-Member -MemberType NoteProperty -Name ErrorType -Value $ErrorType.ToString()
}

# Record end of script
Tracelog "INFO: Script Finished"
$Trace
$ReturnObject

if($ResultStatus -eq 2) {Throw "Script Failure"}
