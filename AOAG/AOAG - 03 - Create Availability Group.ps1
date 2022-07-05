###############################################################################
##
## AOAG - 03 - Create Availability Group
##
###############################################################################

<#

.SYNOPSIS
    Creates the Availability Group with database.

.DESCRIPTION
    Creates the Availability Group with an existing database and joins the
	secondary replica to this group.

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
	
    [string[]]$AGListenerIPAddress = "_NONE_"
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

$AgDatabaseName = $AvailabilityGroupName + "_Test"
$AvailabilityMode = If ($Synchronous -eq "True") {"SynchronousCommit"} Else {"AsynchronousCommit"}
$FailoverMode = If ($Synchronous -eq "True") {"Automatic"} Else {"Manual"}

try {
    # Add script execution start details to trace log
    Tracelog "INFO: Script executing in local PowerShell version [$($PSVersionTable.PSVersion.ToString())] session in a [$([IntPtr]::Size * 8)] bit process"
    Tracelog "INFO: Running as user [$([Environment]::UserDomainName)\$([Environment]::UserName)] on host [$($env:COMPUTERNAME)]"
    Tracelog "INFO: Input Parameters received: `r`n`t`t`t`tPrimaryInstanceServer=[$PrimaryInstanceServer];" + `
                                              "`r`n`t`t`t`tSecondaryInstanceServer=[$SecondaryInstanceServer];" + `
                                              "`r`n`t`t`t`tReadonlyReplicaServers=[$ReadonlyReplicaServers];" + `
                                              "`r`n`t`t`t`tSynchronous=[$Synchronous];" + `
                                              "`r`n`t`t`t`tAvailabilityGroupName=[$AvailabilityGroupName];" + `
                                              "`r`n`t`t`t`tAvailabilityGroupListernerName=[$AvailabilityGroupListenerName];" + `
                                              "`r`n`t`t`t`tAGListenerIPAddress=[$AGListenerIPAddress];"

    $PrimaryInstanceName = ($PrimaryInstanceServer + "\INST1")
    $PrimaryServerFQDN = (“TCP://" + $PrimaryInstanceServer + ".boe.bankofengland.co.uk:5022")

	TraceLog "INFO: Create the primary replica as a template object"
    [Microsoft.SqlServer.Management.Smo.AvailabilityReplica[]]$Replicas = New-SqlAvailabilityReplica -Name $PrimaryInstanceName `
	                                                                                                 -EndpointUrl $PrimaryServerFQDN `
							                 					                                     -AvailabilityMode $AvailabilityMode `
											                 	                                     -FailoverMode $FailoverMode `
	                 					 						                                     -AsTemplate `
					                  							                                     -Version 13

    $SecondaryInstanceName = ($SecondaryInstanceServer + "\INST1")
    $SecondaryServerFQDN = (“TCP://" + $SecondaryInstanceServer + ".boe.bankofengland.co.uk:5022")

    TraceLog ("INFO: Create the secondary replica on " + $SecondaryInstanceName)
    $Replicas += New-SqlAvailabilityReplica -Name $SecondaryInstanceName `
	                                        -EndpointUrl $SecondaryServerFQDN `
		                                    -AvailabilityMode $AvailabilityMode `
		                                    -FailoverMode $FailoverMode `
	                                        -AsTemplate `
		                                    -Version 13

    if ($ReadonlyReplicaServers -ne "_NONE_") {
        TraceLog "INFO: Create the readonly replicas"
        $ReadonlyReplicaInstances = @()
	    foreach($ReadonlyReplicaServer in $ReadonlyReplicaServers) {
            $ReadonlyInstanceName = ($ReadonlyReplicaServer + "\INST1")
            $ReadonlyReplicaInstances += $ReadonlyInstanceName
            $ReadonlyServerFQDN = (“TCP://" + $ReadonlyReplicaServer + ".boe.bankofengland.co.uk:5022")
		
            TraceLog ("INFO: Create the secondary replica on " + $ReadonlyInstanceName)
            $Replicas += New-SqlAvailabilityReplica -Name $ReadonlyInstanceName `
	                                                -EndpointUrl $ReadonlyServerFQDN `
		    	    								-AvailabilityMode “AsynchronousCommit” `
			    	    							-FailoverMode "Manual" `
                                                    -ConnectionModeInSecondaryRole AllowReadIntentConnectionsOnly `
				    		    					-AsTemplate `
					    		    				-Version 13
        }
    }
   
    TraceLog ("INFO: Create database " + $AgDatabaseName + " and backup on Primary")
	$SQLServer = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $PrimaryInstanceName
    $Database = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database -argumentList $SQLServer, $AgDatabaseName
    $Database.RecoveryModel = 1
    $Database.Create()  
	Backup-SqlDatabase -ServerInstance $PrimaryInstanceName -Database $AgDatabaseName -BackupFile ("E:\MSSQL01\Data\Backup\" + $AgDatabaseName + ".BAK") -Initialize
	Backup-SqlDatabase -ServerInstance $PrimaryInstanceName -Database $AgDatabaseName -BackupFile ("E:\MSSQL01\Data\Backup\" + $AgDatabaseName + "_Log.BAK") -Initialize -BackupAction Log

	TraceLog "INFO: Restore AO_Test Database on Secondary: $SecondaryInstanceName"
	Copy-Item ("\\$PrimaryInstanceServer\E`$\MSSQL01\Data\Backup\" + $AgDatabaseName + ".BAK") -Destination "\\$SecondaryInstanceServer\E`$\MSSQL01\Data\Backup"
	Copy-Item ("\\$PrimaryInstanceServer\E`$\MSSQL01\Data\Backup\" + $AgDatabaseName + "_Log.BAK") -Destination "\\$SecondaryInstanceServer\E`$\MSSQL01\Data\Backup"
    Restore-SqlDatabase -ServerInstance $SecondaryInstanceName -Database $AgDatabaseName -BackupFile ("E:\MSSQL01\Data\Backup\" + $AgDatabaseName + ".BAK") -NoRecovery
    Restore-SqlDatabase -ServerInstance $SecondaryInstanceName -Database $AgDatabaseName -BackupFile ("E:\MSSQL01\Data\Backup\" + $AgDatabaseName + "_Log.BAK") -RestoreAction Log -NoRecovery

    if ($ReadonlyReplicaServers -ne "_NONE_") {
    	foreach($ReadonlyReplicaServer in $ReadonlyReplicaServers) {
            $ReadonlyInstanceName = ($ReadonlyReplicaServer + "\INST1")

    		TraceLog "INFO: Restore AO_Test Database on Secondary: $ReadonlyInstanceName"
	        Copy-Item ("\\$PrimaryInstanceServer\E`$\MSSQL01\Data\Backup\" + $AgDatabaseName + ".BAK") -Destination "\\$ReadonlyReplicaServer\E`$\MSSQL01\Data\Backup"
	        Copy-Item ("\\$PrimaryInstanceServer\E`$\MSSQL01\Data\Backup\" + $AgDatabaseName + "_Log.BAK") -Destination "\\$ReadonlyReplicaServer\E`$\MSSQL01\Data\Backup"
            Restore-SqlDatabase -ServerInstance $ReadonlyInstanceName -Database $AgDatabaseName -BackupFile ("E:\MSSQL01\Data\Backup\" + $AgDatabaseName + ".BAK") -NoRecovery
            Restore-SqlDatabase -ServerInstance $ReadonlyInstanceName -Database $AgDatabaseName -BackupFile ("E:\MSSQL01\Data\Backup\" + $AgDatabaseName + "_Log.BAK") -RestoreAction Log -NoRecovery
        }
    }

    TraceLog "INFO: Create the Availability Group"
	$PrimaryServer = Get-Item ("SQLSERVER:\SQL\" + $PrimaryInstanceName)
    New-SqlAvailabilityGroup -InputObject $PrimaryServer `
	                         -Name $AvailabilityGroupName `
							 -AvailabilityReplica $Replicas `
							 -Database $AgDatabaseName `
							 -AutomatedBackupPreference PRIMARY `
							 -DtcSupportEnabled `
                             -DatabaseHealthTrigger

    TraceLog "INFO: Join replicas to the Availability Group"

    Join-SqlAvailabilityGroup -Path (“SQLSERVER:\SQL\" + $SecondaryInstanceName) -Name $AvailabilityGroupName

    if ($ReadonlyReplicaServers -ne "_NONE_") {
    	foreach($ReadonlyReplicaServer in $ReadonlyReplicaServers) {
            $ReadonlyInstanceName = ($ReadonlyReplicaServer + "\INST1")

            Join-SqlAvailabilityGroup -Path (“SQLSERVER:\SQL\" + $ReadonlyInstanceName) -Name $AvailabilityGroupName
        }
    }

    TraceLog "INFO: Join database in the secondary replicas to the Availability Group"
	TraceLog "INFO; Joining $SecondaryInstanceName to Availability Group"
	Add-SqlAvailabilityDatabase -Path (“SQLSERVER:\SQL\" + $SecondaryInstanceName + "\AvailabilityGroups\" + $AvailabilityGroupName) -Database $AgDatabaseName

    if ($ReadonlyReplicaServers -ne "_NONE_") {
    	foreach($ReadonlyReplicaServer in $ReadonlyReplicaServers) {
	        $ReadonlyInstanceName = ($ReadonlyReplicaServer + "\INST1")
	        TraceLog "INFO; Joining $ReadonlyInstanceName to Availability Group"
		    Add-SqlAvailabilityDatabase -Path (“SQLSERVER:\SQL\" + $ReadonlyInstanceName + "\AvailabilityGroups\" + $AvailabilityGroupName) -Database $AgDatabaseName
        }
    }

    if ($AvailabilityGroupListenerName -ne "_NONE_" -and $AGListenerIPAddress -ne "_NONE_") {
        TraceLog "INFO: Create the Availability Group listener name"
        New-SqlAvailabilityGroupListener -Name $AvailabilityGroupListenerName `
	                                     -staticIP $AGListenerIPAddress `
			    						 -Port 2130 `
				    					 -Path (“SQLSERVER:\SQL\" + $PrimaryInstanceName + "\AvailabilityGroups\" + $AvailabilityGroupName)

        if ($ReadonlyReplicaServers -ne "_NONE_") {
    	    foreach($ReadonlyReplicaServer in $ReadonlyReplicaServers) {
                Set-SqlAvailabilityReplica -Path (“SQLSERVER:\SQL\" + $PrimaryInstanceName + "\AvailabilityGroups\" + $AvailabilityGroupName + "\AvailabilityReplicas\" + $ReadonlyReplicaServer + "%5CINST1") `
                                           -ReadonlyRoutingConnectionUrl ("tcp://"+ $ReadonlyReplicaServer + ".boe.bankofengland.co.uk:2130")
            }

            Set-SqlAvailabilityReplica -Path (“SQLSERVER:\SQL\" + $PrimaryInstanceName + "\AvailabilityGroups\" + $AvailabilityGroupName + "\AvailabilityReplicas\" + $PrimaryInstanceServer + "%5CINST1") `
                                       -ReadOnlyRoutingList $ReadonlyReplicaInstances

            Set-SqlAvailabilityReplica -Path (“SQLSERVER:\SQL\" + $PrimaryInstanceName + "\AvailabilityGroups\" + $AvailabilityGroupName + "\AvailabilityReplicas\" + $SecondaryInstanceServer + "%5CINST1") `
                                       -ReadOnlyRoutingList $ReadonlyReplicaInstances

    	    foreach($ReadonlyReplicaServer in $ReadonlyReplicaServers) {
                $ReadonlyReplicaInstancesOrdered = $ReadonlyReplicaInstances -ne ($ReadonlyReplicaServer + "\INST1")
                $ReadonlyReplicaInstancesOrdered += ($ReadonlyReplicaServer + "\INST1")

                Set-SqlAvailabilityReplica -Path (“SQLSERVER:\SQL\" + $PrimaryInstanceName + "\AvailabilityGroups\" + $AvailabilityGroupName + "\AvailabilityReplicas\" + $ReadonlyReplicaServer + "%5CINST1") `
                                           -ReadOnlyRoutingList $ReadonlyReplicaInstancesOrdered
            }
        }
    }

	Tracelog "INFO: Restarting SQL Server"
    net stop 'SQLAGENT$INST1'
    net start 'SQLAGENT$INST1'

	If ((Get-Service -Include 'SQLAgent$INST1').Status -ne "Running") {
		Throw "SQL Agent is unable to start"
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
