###############################################################################
##
## SQLDB - Data
##
###############################################################################

<#

.SYNOPSIS
    Configuration data for a standard SQL Server instance build for SQL 2019

.DESCRIPTION
    Configuration data for a standard SQL Server instance build.

.NOTES
    Version:        1.0.0
    Author:         Ellis Charles
    Creation Date:  03rd February 2021
    Purpose/Change: Initial Draft

#>

@{
    MediaLocations = @{
        SqlMedia = '\\techbuild\sql source\SQL_Server2019\Media\SQL2019DEV'
        SsmsMedia = '\\techbuild\sql source\SQL_Server2019\Media\SSMS'
        UpdatesMedia = '\\techbuild\sql source\SQL_Server2019\Media\Updates'
        RaaPrdMedia = '\\techbuild\sql source\SQL_Server2019\RAA_PRD'
        RaaDevMedia = '\\techbuild\sql source\SQL_Server2019\RAA_DEV'
        ScriptsMedia = '\\techbuild\sql source\SQL_Server2019\BuildAutomation'
    }
	SqlIso = 'en_sql_server_2019_developer_x64_dvd_e5ade34a.iso'

	# Set as an empty string if no Service Pack to be installed
	#SqlCurrentSp = 'SP2\SQLServer2016SP2-KB4052908-x64-ENU.exe'
	#SpVersion = "13.0.5026.0"

	# Set as an empty string if no Cumulative Update to be installed
	#SqlCurrentCu = 'SP2\CU4\SQLServer2016-KB4464106-x64.exe'
	#CuVersion = "13.0.5233.0"
	
	#updated below for Cu8
	# Set as an empty string if no Cumulative Update to be installed
	SqlCurrentCu = 'CU8\SQLServer2019-KB4577194-x64.exe'
	CuVersion = "15.0.4073.23"

	
}
