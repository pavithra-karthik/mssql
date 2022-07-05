###############################################################################
##
## AOAG.Test
##
###############################################################################

<#

.SYNOPSIS
    Pester tests to ensure AOAG deployment has succeeded.

.DESCRIPTION
    Pester tests to ensure AOAG deployment has succeeded.

.PARAMETER ServerName
    The server hosting the SQL Server instance which requires AlwaysOn enabling.

.PARAMETER AgGroupName
    The Availability Group name to test.

.NOTES
    Version:        0.1.7282.25140
    Author:         Brian Poore
    Creation Date:  30th July 2019
    Purpose/Change: Initial Draft

#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$ServerName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$AgGroupName
)

Import-Module -Name Pester
Import-Module -Name SqlServer

Set-StrictMode -Off

$AgPath = "SQLSERVER:\SQL\$ServerName\INST1\AvailabilityGroups\$AgGroupName\DatabaseReplicaStates"
$AgStates = Get-ChildItem $AgPath | Select-Object AvailabilityReplicaServerName,AvailabilityDatabaseName,ReplicaRole,SynchronizationState


Describe -Tags "AOAG" "SQL Server Availability Group Deployment" {
    It "Availability Groups exists" {
		$AgStates.Count | Should BeGreaterThan 0
	}

	It "Availability Groups should be synchronised" {
		(Get-ChildItem $AgPath | Test-SqlDatabaseReplicaState | Where-Object {$_.HealthState -ne "Healthy"}).Count | Should Be 0
	}

	It "SQL Agent service is running" {
        (Get-Service -Include 'SQLAgent$INST1').Status | Should Be "Running"
    }
}
