###############################################################################
##
## SQLDB.Test
##
###############################################################################

<#

.SYNOPSIS
    Pester tests to ensure SQLDB deployment has succeeded.

.DESCRIPTION
    Pester tests to ensure SQLDB deployment has succeeded.

.NOTES
    Version:        0.1.7282.25140
    Author:         Brian Poore
    Creation Date:  26th July 2019
    Purpose/Change: Initial Draft

#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$CollationName
)

Import-Module -Name Pester
Import-Module -Name SqlServer

Set-StrictMode -Off

$ConfigDataPath = "$PSScriptRoot\SQLDB - Data.psd1"
$ConfigData = Import-PowerShellDataFile -Path $ConfigDataPath

$MountPointMissing = $false
$MountPoints = @(
    "E:\MSSQL01\Data"
    "E:\MSSQL01\Data\Backup"
    "E:\MSSQL01\SystemDB"
    "E:\MSSQL01\TempDB"
    "E:\MSSQL01\TLogs"
)

foreach ($MountPoint in $MountPoints) {
    if (-Not (Test-Path -Path $MountPoint)) {$MountPointMissing = $true}
}

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

$SuperSocketKey = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.INST1\MSSQLServer\SuperSocketNetLib'

$TempDBFiles = Get-ChildItem -Path "E:\MSSQL01\TempDB\" | Where-Object {$_.Name -match '.mdf|.ndf'} | Measure-Object -Property Length -Minimum -Maximum
$TempDBLogFiles = Get-ChildItem -Path "E:\MSSQL01\TempDB\" | Where-Object {$_.Name -match '.ldf'} | Measure-Object -Property Length -Minimum -Maximum

$LogicalCpuCount = (Get-WmiObject –class Win32_processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
if ($LogicalCpuCount -gt 8) {$LogicalCpuCount = 8}

$TempDbVolume = Get-Volume -FileSystemLabel "tempdb"
if ($TempDbVolume.GetType().FullName -eq "System.Object[]") {
    $TempDbVolume = $TempDbVolume[0]
}

$TempDBVolumeSize = ([math]::Round($TempDbVolume.size / 10737418240) * 10)
$TempDBFileSize = [Math]::Round(($TempDBVolumeSize * 0.8) / ($LogicalCpuCount + 1)) * 1024
$TempDBLogFileSize =  [Math]::Floor($TempDBFileSize / 2048) * 1024

Describe -Tags "SQLDB" "SQL Server Deployment" {
    It "Mount points should exist" {
		$MountPointMissing | Should Be $false
	}

    It "App Disk block size should be 4KB" {
		(Get-Volume | Where-Object {$_.FileSystemLabel -eq "App"} | Select-Object AllocationUnitSize | Get-Unique).AllocationUnitSize | Should Be 4096
	}

    It "SQL Disk block sizes should be 64KB" {
		($CurrentConfig | Where-Object {$_.BlockSize -ne 65536}).Count | Should Be 0
	}

	It "Partition Offsets should be 129MB" {
	    ($CurrentConfig | Where-Object {$_.Offset -ne 135266304}).Count | Should Be 0
	}

    It "DB Services Group is a member of local administrators" {
        (Get-LocalGroupMember -Group "Administrators" -Member "BOE\ISTD-S DB Services (SQL)").Count | Should Be 1
    }

    It "SQL Server service is running" {
        (Get-Service -Include 'MSSQL$INST1').Status | Should Be "Running"
    }

    It "SQL Agent service is running" {
        (Get-Service -Include 'SQLAgent$INST1').Status | Should Be "Running"
    }

    It "SQL Server is at the correct patch version" {
        (New-Object ("Microsoft.SqlServer.Management.Smo.Server") ($env:COMPUTERNAME + "\INST1")).VersionString | Should Be $ConfigData.CuVersion
    }

    It "SQL Server has the correct Collation" {
        (New-Object ("Microsoft.SqlServer.Management.Smo.Server") ($env:COMPUTERNAME + "\INST1")).Properties["Collation"].Value | Should Be $CollationName
    }

	It "Correct number of tempdb data files exist" {
	    $TempDBFiles.Count | Should be $LogicalCpuCount
	}

	It "Correct number of tempdb log files exist" {
	    $TempDBLogFiles.Count | Should be 1
	}

	It "tempdb data files should be the same size" {
	    $TempDBFiles.Minimum | Should be $TempDBFiles.Maximum
	}

	It "tempdb data files should be the correct size" {
	    $TempDBFiles.Minimum / 1048576 | Should be $TempDBFileSize
	}

	It "tempdb log file should be the correct size" {
	    $TempDBLogFiles.Minimum / 1048576 | Should be $TempDBLogFileSize
	}

    It "SQL Server Management Studio is installed" {
        (Get-WMIObject -Query "SELECT * FROM Win32_Product Where Name Like 'SQL Server%Management Studio'").Length | Should BeGreaterThan 0
    }

	It "Named Pipes network library is disabled" {
	    (Get-Item ($SuperSocketKey + "\Np")).GetValue('Enabled') | Should Be 0
	}

	It "TCP Network library is enabled" {
	    (Get-Item ($SuperSocketKey + "\Tcp")).GetValue('Enabled')
	}

	It "SQL Server listening on TCP Port 2130" {
	    (Get-Item ($SuperSocketKey + "\Tcp\IpAll")).GetValue('TcpPort')
	}

	It "CEIP Service Stopped" {
		(Get-Service -Name "*TELEMETRY*" | Where-Object {$_.Status -ne "Stopped"}).Count | should Be 0
	}

	It "CEIP Service Disabled" {
	    (Get-Service -Name "*TELEMETRY*" | Where-Object {$_.StartType -ne "Disabled"}).Count | should Be 0
	}
}
