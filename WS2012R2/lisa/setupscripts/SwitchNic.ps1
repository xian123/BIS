############################################################################
#
# AddNic.ps1
#
# Description:
#
#
#   The ICA scripts will always pass the vmName, hvServer, and a
#   string of testParams from the test definition separated by
#   semicolons. The testParams for this script identify disk
#   controllers, hard drives, and .vhd types.  The testParams
#   have the format of:
#
#      NIC=NIC type, Network Type, Network Name
#
#   NIC Type can be one of the following:
#      NetworkAdapter
#      LegacyNetworkAdapter
#
#   Network Type can be one of the following:
#      External
#      Internal
#      Private
#
#   Network Name is the name of a existing netowrk.
#
#   This script will not create the network.  It will make sure the network
#   exists.
#
#   The following is an example of a testParam for adding a NIC
#
#     <testParams>
#         <param>NIC=NetworkAdapter,External,Corp Ethernet LAN</param>
#         <param>NIC=LegacyNetworkAdapter,Internal,InternalNet</param>
#     <testParams>
#
#   The above will be parsed into the following string by the ICA scripts and passed
#   to the setup script:
#
#       "NIC=NetworkAdapter,External,Corp Ehternet LAN";NIC=LegacyNetworkAdapter,Internal,InternalNet"
#
#   The setup (and cleanup) scripts need to parse the testParam
#   string to find any parameters it needs.
#
#   Notes:
#     This is a setup script that will run before the VM is booted.
#     This script will add a NIC to the VM.
#
#     Setup scripts (and cleanup scripts) are run in a separate
#     PowerShell environment, so they do not have access to the
#     environment running the ICA scripts.  Since this script uses
#     The PowerShell Hyper-V library, these modules must be loaded
#     by this startup script.
#
#     The .xml entry for this script could look like either of the
#     following:
#         <setupScript>SetupScripts\AddNic.ps1</setupScript>
#
#   All setup and cleanup scripts must return a boolean ($true or $false)
#   to indicate if the script completed successfully or not.
#
############################################################################

param([string] $vmName, [string] $hvServer, [string] $testParams)

$retVal = $False

"SwitchNIC.ps1"
"VM Name   = ${vmName}"
"HV Server = ${hvServer}"
"TestParams= ${testParams}"
#
# Check input arguments
#
#
if (-not $vmName)
{
    "Error: VM name is null. "
    return $retVal
}

if (-not $hvServer)
{
    "Error: hvServer is null"
    return $retVal
}
#
# Parse the testParams string
#
$rootDir = $null

$params = $testParams.Split(';')
foreach ($p in $params)
{
    if ($p.Trim().Length -eq 0)
    {
        continue
    }

    $tokens = $p.Trim().Split('=')
    
    if ($tokens.Length -ne 2)
    {
	"Warn : test parameter '$p' is being ignored because it appears to be malformed"
     continue
    }
    
    if ($tokens[0].Trim() -eq "RootDir")
    {
        $rootDir = $tokens[1].Trim()
    }
    
}

if ($rootDir -eq $null)
{
    "Error: The RootDir test parameter is not defined."
    return $False
}

cd $rootDir

#
#
#
$summaryLog  = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers TC124" | Out-File $summaryLog


#
# Switch the NIC of the VM
#
 $snic = Get-VMNetworkAdapter -VMName $vmName
 Write-Output $snic | Out-File -Append $summaryLog
 if( $snic.Length -ne 2 )
 {
     "Error: Switch Network Adaptor is not equal to 2"
     return $False
 }
 
 $switchName = "Internal"
 $snic[-1] | Connect-VMNetworkAdapter -SwitchName $switchName
 $switch = Get-VMNetworkAdapter -VMName $vmName
 if ($switch[-1].SwitchName -ne $switchName)
  {
    "Error: Unable to Switch Network Adaptor Type"
     return $False
  }
  else
  {
  $retVal = $true
  "Network type switched"
  }

return $retVal
