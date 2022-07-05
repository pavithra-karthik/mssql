###############################################################################
##
## AOAG - Deploy AlwaysOn
##
###############################################################################

<#

.SYNOPSIS
    Deploys an AlwaysOn Availability Group.

.DESCRIPTION
    Calls each of the installation scripts on a remote server which requires
    AlwaysOn deploying to it.

.PARAMETER PrimaryInstanceServer
    The server hosting the SQL Server instance where the Primary replica resides.

.PARAMETER SecondaryInstanceServer
    The server hosting SQL Server instances where the secondary replica resides.

.PARAMETER ReadonlyReplicaServers
    An array of servers hosting SQL Server instances where the readonly replicas reside.

.PARAMETER Synchronous
    Whether the Availability Group uses Synchronous commit or not.

.PARAMETER AvailabilityGroupName
    The desired name for the Availability group

.PARAMETER AvailabilityGroupListernerName
    The name of the availability Group listener

.PARAMETER AGListenerIPAddress
   The IP Address to be used for the Availability Group	listener

.PARAMETER ServiceAccount
    The service account of the other SQL Server instance involved in The
	Availability Group.

.NOTES
    Version:        0.1.7282.25140
    Author:         Brian Poore
    Creation Date:  5th September 2019
    Purpose/Change: Initial Draft

.EXAMPLE 2 Node Synchronous

    & '.\AOAG - Deploy AlwaysOn.ps1'

    cmdlet AOAG - Deploy AlwaysOn.ps1 at command pipeline position 1
    Supply values for the following parameters:
    PrimaryInstanceServer: SQLAG-DW-SQL2A
    SecondaryInstanceServer: SQLAG-DW-SQL2C
    Synchronous: True
    AvailabilityGroupName: AO2Synch
    ServiceAccount: BOE\SS-SQLAGDWSQL2$

.EXAMPLE 2 Node Asynchronous

    & '.\AOAG - Deploy AlwaysOn.ps1'

    cmdlet AOAG - Deploy AlwaysOn.ps1 at command pipeline position 1
    Supply values for the following parameters:
    PrimaryInstanceServer: SQLAG-DW-SQL2B
    SecondaryInstanceServer: SQLAG-DW-SQL2D
    Synchronous: False
    AvailabilityGroupName: AO2Asynch
    ServiceAccount: BOE\SS-SQLAGDWSQL2$

.EXAMPLE 4 Node no listener

    & '.\AOAG - Deploy AlwaysOn.ps1' -ReadonlyReplicaServers "SQLAG-DW-SQL2B", "SQLAG-DW-SQL2D"

    cmdlet AOAG - Deploy AlwaysOn.ps1 at command pipeline position 1
    Supply values for the following parameters:
    PrimaryInstanceServer: SQLAG-DW-SQL2A
    SecondaryInstanceServer: SQLAG-DW-SQL2C
    Synchronous: True
    AvailabilityGroupName: AO4NoListener
    ServiceAccount: BOE\SS-SQLAGDWSQL2$

.EXAMPLE 4 Node with listener

    & '.\AOAG - Deploy AlwaysOn.ps1' -ReadonlyReplicaServers "SQLAG-DW-SQL2B", "SQLAG-DW-SQL2D" -AvailabilityGroupListenerName "SQLAGDWSQL2-L1" -AGListenerIPAddress "10.72.65.102/255.255.255.0", "10.72.68.16/255.255.255.0"

    cmdlet AOAG - Deploy AlwaysOn.ps1 at command pipeline position 1
    Supply values for the following parameters:
    PrimaryInstanceServer: SQLAG-DW-SQL2A
    SecondaryInstanceServer: SQLAG-DW-SQL2C
    Synchronous: True
    AvailabilityGroupName: AO4Listener
    ServiceAccount: BOE\SS-SQLAGDWSQL2$

#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$PrimaryInstanceServer,

	[Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$SecondaryInstanceServer,

    [string[]]$ReadonlyReplicaServers = "_NONE_",

	[Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$Synchronous,

	[Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$AvailabilityGroupName,

    [string]$AvailabilityGroupListenerName = "_NONE_",
	
    [string[]]$AGListenerIPAddress = "_NONE_",

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceAccount
)

$ErrorActionPreference = "Stop"

$LogFile = $PSScriptRoot + "\" + $PrimaryInstanceServer + "---" + $AvailabilityGroupName + "-Build-AlwaysOn.log"

try {
    "Deploying AlwaysOn Availability Group " + $AvailabilityGroupName | Out-File -FilePath $LogFile

    Write-Progress -Activity 'AlwaysOn Deployment' -Status 'Step 1: Enable AlwaysOn on Primary' -PercentComplete 12
    & ($PSScriptRoot + "\AOAG - 01 - Enable AlwaysOn.ps1") -ServerName $PrimaryInstanceServer | Tee-Object -FilePath $LogFile -Append

    Write-Progress -Activity 'AlwaysOn Deployment' -Status 'Step 2: Enable AlwaysOn on Secondary' -PercentComplete 24
    & ($PSScriptRoot + "\AOAG - 01 - Enable AlwaysOn.ps1") -ServerName $SecondaryInstanceServer | Tee-Object -FilePath $LogFile -Append

    if ($ReadonlyReplicaServers -ne "_NONE_") {
        Write-Progress -Activity 'AlwaysOn Deployment' -Status 'Step 3: Enable AlwaysOn on Readonly Servers' -PercentComplete 36
        foreach ($ReadonlyReplicaServer in $ReadonlyReplicaServers) {
            & ($PSScriptRoot + "\AOAG - 01 - Enable AlwaysOn.ps1") -ServerName $ReadonlyReplicaServer | Tee-Object -FilePath $LogFile -Append
        }
    }

    Write-Progress -Activity 'AlwaysOn Deployment' -Status 'Step 4: Configure endpoints on Primary' -PercentComplete 48
    & ($PSScriptRoot + "\AOAG - 02 - Configure Endpoints.ps1") -ServerName $PrimaryInstanceServer -ServiceAccount $ServiceAccount | Tee-Object -FilePath $LogFile -Append

    Write-Progress -Activity 'AlwaysOn Deployment' -Status 'Step 5: Configure endpoints on Secondary' -PercentComplete 60
    & ($PSScriptRoot + "\AOAG - 02 - Configure Endpoints.ps1") -ServerName $SecondaryInstanceServer -ServiceAccount $ServiceAccount | Tee-Object -FilePath $LogFile -Append

    if ($ReadonlyReplicaServers -ne "_NONE_") {
        Write-Progress -Activity 'AlwaysOn Deployment' -Status 'Step 6: Configure endpoints on Readonly Servers' -PercentComplete 72
        foreach ($ReadonlyReplicaServer in $ReadonlyReplicaServers) {
            & ($PSScriptRoot + "\AOAG - 02 - Configure Endpoints.ps1") -ServerName $ReadonlyReplicaServer -ServiceAccount $ServiceAccount | Tee-Object -FilePath $LogFile -Append
        }
    }

    Write-Progress -Activity 'AlwaysOn Deployment' -Status 'Step 7: Create Availability Group' -PercentComplete 84
    & ($PSScriptRoot + "\AOAG - 03 - Create Availability Group.ps1") -PrimaryInstanceServer $PrimaryInstanceServer `
                                                                     -SecondaryInstanceServer $SecondaryInstanceServer `
                                                                     -ReadonlyReplicaServers $ReadonlyReplicaServers `
                                                                     -Synchronous $Synchronous `
                                                                     -AvailabilityGroupName $AvailabilityGroupName `
                                                                     -AvailabilityGroupListenerName $AvailabilityGroupListenerName `
                                                                     -AGListenerIPAddress $AGListenerIPAddress | Tee-Object -FilePath $LogFile -Append

	Write-Progress -Activity 'AlwaysOn Deployment' -Status 'Step 8: Test deployment' -Completed
	& ($PSScriptRoot + "\AOAG.Test.ps1") -ServerName $PrimaryInstanceServer -AgGroupName $AvailabilityGroupName | Tee-Object -FilePath $LogFile -Append
}
catch {
}
finally {
}
