###############################################################################
##
## SQLDB - 04 - Post-install SQL Scripts
##
###############################################################################

<#

.SYNOPSIS
    Executes the post-install build scripts.

.DESCRIPTION
    Executes all the SQL scrips that exist in:

	    \\techbuild\SQL Source\SQL_Server2019\BuildAutomation\Scripts

	and all subdirectories. These are copied locally during the inial
	installation.

.PARAMETER Environment
    The environment tier, DEV, UAT, PRD, that the instance is implemented
	in.

.NOTES
    Version:        1.0.1
    Author:         Ellis Charles
    Creation Date:  03rd Feb 2021
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

[string]$InstanceName =  "$env:COMPUTERNAME\INST1"

try {
    # Add script execution start details to trace log
    Tracelog "INFO: Script executing in local PowerShell version [$($PSVersionTable.PSVersion.ToString())] session in a [$([IntPtr]::Size * 8)] bit process"
    Tracelog "INFO: Running as user [$([Environment]::UserDomainName)\$([Environment]::UserName)] on host [$($env:COMPUTERNAME)]"
    Tracelog "INFO: Input Parameters received: `r`n`t`t`t`tEnvironment=[$Environment]; `r`n`t`t`t`tInstanceName=[$InstanceName]"
	
	Tracelog "INFO: Copying current scripts to local drive"
	robocopy /MIR /ETA '\\techbuild\SQL Source\SQL_Server2019\BuildAutomation\Scripts' 'C:\dbservices\BuildAutomation\Scripts\'

	Tracelog "INFO: Retrieve list of SQL files to execute"
	$Directory = Get-ChildItem "C:\dbservices\BuildAutomation\Scripts\" -recurse | Sort-Object Name
        
    if ($Environment -ne 'DEV') {
        $SQLFiles = $Directory | where {$_.Extension-eq ".SQL" -and $_.Name -notmatch "DEV SERVERS ONLY*" }
    }
    else {
        $SQLFiles = $Directory | where {$_.Extension -eq ".SQL" } 
    }
	   
    foreach ($SQLFile in $SQLFiles)
    {
	    Tracelog "INFO: Executiong $($SQLFile.FullName)"
        try {
            Invoke-Sqlcmd -QueryTimeout 300 -ServerInstance $InstanceName -InputFile $SQLFile.FullName | Out-File -Append -FilePath "C:\dbservices\BuildAutomation\Scripts\outputScripts.log"
        } catch {}
    }
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
