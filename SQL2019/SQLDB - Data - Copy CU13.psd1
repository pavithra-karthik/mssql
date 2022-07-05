###############################################################################
##
## SQLDB - Data
##
###############################################################################

<#

.SYNOPSIS
    Configuration data for a standard SQL Server instance build.

.DESCRIPTION
    Configuration data for a standard SQL Server instance build.

.NOTES
    Version:        0.1.7282.25140
    Author:         Brian Poore
    Creation Date:  03rd July 2019
    Purpose/Change: Initial Draft

#>

@{
    MediaLocations = @{
        SqlMedia = '\\techbuild\sql source\SQL2016Install\Media\SQL2016ENT'
        SsmsMedia = '\\techbuild\sql source\SQL2016Install\Media\SSMS'
        UpdatesMedia = '\\techbuild\sql source\SQL2016Install\Media\Updates'
        RaaPrdMedia = '\\techbuild\sql source\SQL2016Install\RAA_PRD'
        RaaDevMedia = '\\techbuild\sql source\SQL2016Install\RAA_DEV'
        ScriptsMedia = '\\techbuild\sql source\SQL2016Install\BuildAutomation'
    }
	SqlIso = 'SW_DVD9_NTRL_SQL_Svr_Ent_Core_2016w_SP1_64Bit_English_OEM_VL_X21-22132.iso'

	# Set as an empty string if no Service Pack to be installed
	SqlCurrentSp = 'SP2\SQLServer2016SP2-KB4052908-x64-ENU.exe'
	SpVersion = "13.0.5026.0"

	# Set as an empty string if no Cumulative Update to be installed
	#SqlCurrentCu = 'SP2\CU4\SQLServer2016-KB4464106-x64.exe'
	#CuVersion = "13.0.5233.0"
	
	#updated below for Cu13
	# Set as an empty string if no Cumulative Update to be installed
	SqlCurrentCu = 'SP2\CU13\sqlserver2016-kb4549825-x64_5e5785ee0bf5444f7a57a6c559a1d9ef6b785860.exe'
	CuVersion = "13.0.5820.21"


}
