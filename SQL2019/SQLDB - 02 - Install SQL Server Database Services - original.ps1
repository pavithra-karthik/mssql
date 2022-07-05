###############################################################################
##
## SQLDB - 02 - Install SQL Server Database Services
##
###############################################################################

<#

.SYNOPSIS
    Installs the SQL Server Database Services.

.DESCRIPTION
    Calls the SQL setup application found in the defult installation media
    directory once created.

.PARAMETER ServiceAccountName
    The service account created for SQL Server database services on this
    server.

.PARAMETER AGTServiceAccountName
    The service account created for SQL Agent on this server.

.NOTES
    Version:        1.0.1
    Author:         Ellis Charles
    Creation Date:  03th Feb 2021
    Purpose/Change: Initial Draft for SQL 2019 DEV install

.OUTPUTS
    ResultStatus: "0 - Success, 1 - Warning, 2 - Failure"
    ErrorMessage: "Error Message caught/written during script execution ("Success" if resultstatus = "0")"
    ErrorType:    "The error type caught during script execution ("Success" if resultstatus = "0")"
    Trace:        "Script Activity Trace"

#>

param(
    [Parameter()]
    [string]$SQLServiceAccountName,

    [Parameter()]
    [string]$AGTServiceAccountName,

    [Parameter()]
    [string]$CollationName
)

$ConfigDataPath = "$PSScriptRoot\SQLDB - Data.psd1"
$ConfigData = Import-PowerShellDataFile -Path $ConfigDataPath

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

[String]$MediaPath = "C:\DBServices\"

[String]$Collation = $CollationName
[String]$SQLServiceAccount = $SQLServiceAccountName
[String]$AGTServiceAccount = $AGTServiceAccountName
[String]$ServerName = $env:COMPUTERNAME
$ServerName -match "([A-Z0-9]+)-([A-Z]+)-([A-Z]+\d+)[A-Z]?" | Out-Null

if ($Collation -eq '') {
    $Collation = 'Latin1_General_CI_AS'
}

if ($SQLServiceAccount -eq '') {
    $SQLServiceAccount = "SS-" + $Matches.1 + $Matches.2 + $Matches.3 + "$"
}

if ($AGTServiceAccount -eq '') {
    $AGTServiceAccount = "SA-" + $Matches.1 + $Matches.2 + $Matches.3 + "$"
}

try {
    # Add script execution start details to trace log
    Tracelog "INFO: Script executing in local PowerShell version [$($PSVersionTable.PSVersion.ToString())] session in a [$([IntPtr]::Size * 8)] bit process"
    Tracelog "INFO: Running as user [$([Environment]::UserDomainName)\$([Environment]::UserName)] on host [$($env:COMPUTERNAME)]"
    Tracelog "INFO: Input Parameters received: `r`n`t`t`t`tSQLServiceAccountName=[$SQLServiceAccount]; `r`n`t`t`t`tAGTServiceAccountName=[$AGTServiceAccount]; `r`n`t`t`t`tCollation=[$Collation]"

	Tracelog "INFO: Checking service accounts exist"
	Get-ADServiceAccount -Identity $SQLServiceAccount | Out-Null
	Get-ADServiceAccount -Identity $AGTServiceAccount | Out-Null

	##### Need to interrogate CyberArk and extract moxiereader password if exists ####
    TraceLog "INFO: Creating an sa password"
    [string]$saPassword = ([char[]]([char]33..[char]95) + ([char[]]([char]97..[char]126)) + 0..9 | sort {Get-Random})[0..15] -join ''

    TraceLog "INFO: Storing sa password in CyberArk"
    ##### Needs to be stored in CyberArk #####
        
    TraceLog "INFO: Copying SQL Server installation media to local drive"
    New-Item $MediaPath -ItemType "directory" -Force | Out-Null
    Copy-Item $ConfigData.MediaLocations.SqlMedia  -Destination $MediaPath -Recurse -Force | Out-Null
    Copy-Item $ConfigData.MediaLocations.SsmsMedia  -Destination $MediaPath -Recurse -Force | Out-Null
    Copy-Item $ConfigData.MediaLocations.UpdatesMedia -Destination $MediaPath -Recurse -Force | Out-Null
    Copy-Item $ConfigData.MediaLocations.RaaPrdMedia -Destination $MediaPath -Recurse -Force | Out-Null
    Copy-Item $ConfigData.MediaLocations.RaaDevMedia -Destination $MediaPath -Recurse -Force | Out-Null
    Copy-Item $ConfigData.MediaLocations.ScriptsMedia -Destination $MediaPath -Recurse -Force | Out-Null
    Get-ChildItem -Recurse -Path "$MediaPath\Updates" | Unblock-File
    
	try {
	    Get-Service -Name 'MSSQL$INST1' | Out-Null
		TraceLog "SKIP: SQL Server named instance INST1 already exists"
	}
	catch {
		TraceLog "INFO: Mounting ISO Image"
        $ISOVolume = Mount-DiskImage -ImagePath ($MediaPath + "SQL2019DEV\" + $ConfigData.SqlIso) -PassThru | Get-Volume
    	$DriveInfo = Get-PSDrive -Name $ISOVolume.DriveLetter

    	TraceLog ("INFO: Copying media files from ISO to $MediaPath\SQL2019DEV")
        robocopy /xc /xn /xo /e /np /nfl /ndl $driveInfo.Root "$MediaPath\SQL2019DEV" | Out-Null
    	Dismount-DiskImage -ImagePath ($MediaPath + "SQL2019DEV\" + $ConfigData.SqlIso)

    	TraceLog "INFO: Slipstreaming service pack and cumulative update"
    	New-Item ($MediaPath + "SQL2019DEV\updates\") -ItemType "directory" -Force | Out-Null
        Copy-Item ($MediaPath + "Updates\" + $ConfigData.SqlCurrentSp) -Destination ($MediaPath + "SQL2019DEV\updates\") -Force | Out-Null
    	Copy-Item ($MediaPath + "Updates\" + $ConfigData.SqlCurrentCu) -Destination ($MediaPath + "SQL2019DEV\updates\") -Force | Out-Null

        TraceLog "INFO: Installing SQL Server Database Services"
        $SetupPath="$MediaPath\SQL2019DEV\setup.exe"
        $Arguments="/CONFIGURATIONFILE=`"$PSScriptRoot\SQLDB_ConfigurationFile.ini`" /SQLCOLLATION=`"$Collation`" /SQLSVCACCOUNT=`"BOE\$SQLServiceAccount`" /AGTSVCACCOUNT=`"BOE\$AGTServiceAccount`" /SAPWD=`"$saPassword`" "

        Start-Process -FilePath $SetupPath -argumentList $Arguments -wait
	}

    TraceLog "INFO: Checking SQL Server is installed and running"
	if ((Get-Service -Name 'MSSQL$INST1').Status -ne 'Running') {
	    Throw 'SQL Server service is not running'
	}

	if ((Get-WMIObject -Query "SELECT * FROM Win32_Product Where Name Like 'SQL Server%Management Studio'").Length -eq 0) {
	    TraceLog "INFO: Installing SSMS"
	    Start-Process -FilePath "C:\DBServices\SSMS_18_6\SSMS-Setup-ENU (3).exe" -ArgumentList "/install /quiet /passive /norestart" -wait
	}
	else {
		TraceLog "SKIP: SSMS Already installed"
	}

	if ((Get-WMIObject -Query "SELECT * FROM Win32_Product Where Name Like 'SQL Server%Management Studio'").Length -eq 0) {
	    $ResultStatus = '2'
        $ErrorMessage = "SQL Server Management Studio failed to install"
        $ErrorType = "SQL Server Management Studio failed to install"

        Tracelog "WARN: SQL Server Management Studio failed to install"
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
