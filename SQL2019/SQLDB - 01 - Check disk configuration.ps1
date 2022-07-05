###############################################################################
##
## SQLDB - 01 - Check disk configuration
##
###############################################################################

<#

.SYNOPSIS
    Checks mount points exist, block sizes and offsets are correct.

.DESCRIPTION
    Checks mount points exist, block sizes and offsets are correct.

.NOTES
    Version:        0.1.7282.25140
    Author:         Brian Poore
    Creation Date:  29th July 2019
    Purpose/Change: Initial Draft

.OUTPUTS
    ResultStatus: "0 - Success, 1 - Warning, 2 - Failure"
    ErrorMessage: "Error Message caught/written during script execution ("Success" if resultstatus = "0")"
    ErrorType:    "The error type caught during script execution ("Success" if resultstatus = "0")"
    Trace:        "Script Activity Trace"

#>

# Define "Tracelog" function for writing to Trace (remote sessions when used
# will append an external log to this log on completi$on using an "Appendlog"
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

try {
    # Add script execution start details to trace log
    Tracelog "INFO: Script executing in local PowerShell version [$($PSVersionTable.PSVersion.ToString())] session in a [$([IntPtr]::Size * 8)] bit process"
    Tracelog "INFO: Running as user [$([Environment]::UserDomainName)\$([Environment]::UserName)] on host [$($env:COMPUTERNAME)]"

    TraceLog "INFO: Checking mount points exist"
    $MountPoints = @(
        "E:\MSSQL01\Data"
        "E:\MSSQL01\SystemDB"
        "E:\MSSQL01\TempDB"
        "E:\MSSQL01\TLogs"
    )

    foreach ($MountPoint in $MountPoints) {
        if (-Not (Test-Path -Path $MountPoint)) {
		    Throw ("Mount point not found: " + $MountPoint)
	    }
    }

	TraceLog "INFO: Checking App drive block size is 4KB"
	if ((Get-Volume | Where-Object {$_.FileSystemLabel -eq "App"} | Select-Object AllocationUnitSize | Get-Unique).AllocationUnitSize -ne 4096) {
        Throw "Apps drive block size is not 4KB"
    }

	TraceLog "INFO: Checking SQL drives block sizes are 64KB and offsets are 129MB"
    $CurrentConfig = @()
    $Volumes = Get-Volume | Where-Object {$_.FileSystemLabel -In "SystemDB", "Tlogs", "TempDB", "Data"}

    foreach ($Volume in $Volumes) {
        $Partition = Get-Partition -Volume $Volume
    
        $VolumeDetail = New-Object -TypeName PsObject
        $VolumeDetail | Add-Member -MemberType NoteProperty -Name "Label" -Value  $Volume.FileSystemLabel
        $VolumeDetail | Add-Member -MemberType NoteProperty -Name "BlockSize" -Value $Volume.AllocationUnitSize
        $VolumeDetail | Add-Member -MemberType NoteProperty -Name "Offset" -Value $Partition.Offset

        $CurrentConfig += $VolumeDetail
    }

    if (($CurrentConfig | Where-Object {$_.BlockSize -ne 65536}).Count -ne 0 -or ($CurrentConfig | Where-Object {$_.Offset -ne 135266304}).Count -ne 0) {
        Throw "Disk Configuration Incorrect"
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
