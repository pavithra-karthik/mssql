###############################################################################
##
## AOAG - 02 - Configure Endpoints
##
###############################################################################

<#

.SYNOPSIS
    Creates the Availability Group endpoint.

.DESCRIPTION
    Creates and starts the Availability Group endpioint, and starts is. Also
	creates the login for the service account of the other member of the group.

.PARAMETER ServerName
    The server hosting the SQL Server instance which requires AlwaysOn enabling.

.PARAMETER ServiceAccount
    The service account of the other SQL Server instance involved in The
	Availability Group.

.NOTES
    Version:        0.1.7282.25140
    Author:         Brian Poore
    Creation Date:  12th June 2019
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
    [string]$ServerName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceAccount
)

Import-Module sqlserver -DisableNameChecking

# Define "Tracelog" function for writing to Trace (remote sessions when used
# will append an external log to this log on completion using an "Appendlog"
# function, defined in the remote session)
Function Tracelog ([string]$Message) {
    $Script:CurrentAction = $Message
    $Script:Trace += ((Get-Date).ToString() + "`t" + $Message + " `r`n")
}

# Force Declaration of all variables
Set-StrictMode -Version Latest

# Set error Action Global Preference
[string]$ErrorActionPreference = 'Stop'
[int]$ResultStatus = 0
[string]$ErrorMessage = "Success"
[string]$ErrorType = "Success"

[string]$Trace = (get-Date).ToString() + "`t" + "INFO: Runbook Script Trace Started : " + $MyInvocation.MyCommand.Name + " `r`n"

$InstanceName = ($ServerName + "\INST1")

try {
    # Add script execution start details to trace log
    Tracelog "INFO: Script executing in local PowerShell version [$($PSVersionTable.PSVersion.ToString())] session in a [$([IntPtr]::Size * 8)] bit process"
    Tracelog "INFO: Running as user [$([Environment]::UserDomainName)\$([Environment]::UserName)] on host [$($env:COMPUTERNAME)]"
    Tracelog "INFO: Input Parameters received: `r`n`t`t`t`tInstanceName=[$InstanceName];" + `
                                              "`r`n`t`t`t`tServiceAccount=[$ServiceAccount]"

    TraceLog "INFO: Create new Availability Group endpoint"
	try {
        New-SqlHADREndpoint -Path ("SQLSERVER:\SQL\" + $InstanceName) -Name "Hadr_endpoint" -Port 5022 -EncryptionAlgorithm Aes -Encryption Required
    }
    catch {
        TraceLog "SKIP: Availability Group Endpoint exists"
    }

    TraceLog "INFO: Starting new Availability Group endpoint"
    Set-SqlHADREndpoint -Path ("SQLSERVER:\SQL\" + $InstanceName + "\Endpoints\Hadr_endpoint") -State Started

    TraceLog "INFO: Create login for other server in AG"
    $createLogin = “if NOT EXISTS (SELECT 1 FROM syslogins WHERE name = '" + $ServiceAccount + "') BEGIN; CREATE LOGIN [" + $ServiceAccount + "] FROM WINDOWS; END”
    Invoke-SqlCmd -ServerInstance $InstanceName -Query $createLogin

    TraceLog "INFO: Grant access to login to new endpoint"
    $grantConnectPermissions = “GRANT CONNECT ON ENDPOINT::Hadr_endpoint TO [" + $ServiceAccount + "];”
    Invoke-SqlCmd -ServerInstance $InstanceName -Query $grantConnectPermissions 
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
