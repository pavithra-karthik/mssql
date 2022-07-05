###############################################################################
##
## SQLDB - Deploy SQL Server
##
###############################################################################

<#

.SYNOPSIS
    Deploys SQL Server as per the current standard.

.DESCRIPTION
    Calls each of the installation scripts on a remote server which requires
    SQL Server deploying to it.

.PARAMETER Environment
    The environment tier, DEV, UAT, PRD, that the instance is implemented
	in.

.NOTES
    Version:        0.1.7282.25140
    Author:         Brian Poore
    Creation Date:  26th July 2019
    Purpose/Change: Initial Draft

#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Environment,

	[Parameter()]
    [string]$SQLServiceAccountName,

    [Parameter()]
    [string]$AGTServiceAccountName,

    [Parameter()]
    [string]$CollationName
)

$ErrorActionPreference = "Stop"

$LogFile = $PSScriptRoot + "\" + $ENV:COMPUTERNAME + "-Build-SQLServer.log"

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
    "Deploying SQL Server to " + $ENV:COMPUTERNAME | Out-File -FilePath $LogFile

    Write-Progress -Activity 'SQL Server Deployment' -Status 'Step 1: Check Disk Configuration' -PercentComplete 20
    & ($PSScriptRoot + "\SQLDB - 01 - Check disk configuration.ps1") | Tee-Object -FilePath $LogFile -Append

    Write-Progress -Activity 'SQL Server Deployment' -Status 'Step 2: Install SQL Server' -PercentComplete 40
    & ($PSScriptRoot + "\SQLDB - 02 - Install SQL Server Database Services.ps1") -SQLServiceAccountName $SQLServiceAccount -AGTServiceAccountName $AGTServiceAccount -CollationName $Collation | Tee-Object -FilePath $LogFile -Append

    Write-Progress -Activity 'SQL Server Deployment' -Status 'Step 3: Post-install configuration' -PercentComplete 60
    & ($PSScriptRoot + "\SQLDB - 03 - Post-install Configuration.ps1")  -Environment $Environment | Tee-Object -FilePath $LogFile -Append

    Write-Progress -Activity 'SQL Server Deployment' -Status 'Step 4: Post-install SQL Scripts' -PercentComplete 80
    & ($PSScriptRoot + "\SQLDB - 04 - Post-install SQL Scripts.ps1")  -Environment $Environment | Tee-Object -FilePath $LogFile -Append

	Write-Progress -Activity 'SQL Server Deployment' -Status 'Step 5: Test deployment' -Completed
	& ($PSScriptRoot + "\SQLDB.Test.ps1") -CollationName $Collation | Tee-Object -FilePath $LogFile -Append
}
catch {
}
finally {
}






