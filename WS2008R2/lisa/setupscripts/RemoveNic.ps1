############################################################################
#
# RemoveNic.ps1
#
# Description:
#   Remove the NIC with the specific MAC address.
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
#   This script will make sure the network exists.
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

$retVal = $false

#
# Check input arguments
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
# Note: length 22 is the shortest sting possible
#
if (-not $testParams -or $testParams.Length -lt 22)
{
    "Error: No testParams provided"
    "       The script $MyInvocation.InvocationName requires the VCPU test parameter"
    return $retVal
}

#
# Load the HyperVLib version 2 modules
#
$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2SP1\Hyperv.psd1
}

#
# Parse the testParams string, then process each parameter
#
$params = $testParams.Split(';')
foreach ($p in $params)
{
    $temp = $p.Trim().Split('=')
    
    if ($temp.Length -ne 2)
    {
        # Ignore and move on to the next parameter
        continue
    }
    
    #
    # Is this a NIC=* parameter
    #
    if ($temp[0].Trim() -eq "NIC")
    {
        $nicArgs = $temp[1].Split(',')
        
        if ($nicArgs.Length -ne 3)
        {
            "Error: Incorrect number of arguments for NIC test parameter: $p"
            return $false

        }
        
        $nicType = $nicArgs[0].Trim()
        $networkType = $nicArgs[1].Trim()
        $networkName = $nicArgs[2].Trim()
        #$macAddress = $nicArgs[3].Trim()
        $legacy = $false
        
        #
        # Validate the network adapter type
        #
        if (@("NetworkAdapter", "LegacyNetworkAdapter") -notcontains $nicType)
        {
            "Error: Invalid NIC type: $nicType"
            "       Must be either 'NetworkAdapter' or 'LegacyNetworkAdapter'"
            return $false
        }
        
        if ($nicType -eq "LegacyNetworkAdapter")
        {
            $legacy = $true
        }

        #
        # Validate the Network type
        #
        if (@("External", "Internal", "Private") -notcontains $networkType)
        {
            "Error: Invalid netowrk type: $networkType"
            "       Network type must be either: External, Internal, Private"
            return $false
        }

        #
        #
        # Make sure the network exists
        #
        $vmSwitch = Get-VMSwitch -VirtualSwitchName $networkName -server $hvServer
        if (-not $vmSwitch -or $vmSwitch.__CLASS -ne "Msvm_VirtualSwitch")
        {
            "Error: Invalid network name: $networkName"
            "       The network does not exist"
            return $false
        }

        #
        # Validate the MAC is the correct length
        #
        #if ($macAddress.Length -ne 12)
        #{
        #    "Error: Invalid mac address: $p"
        #    return $false
        #}
        
        #
        # Make sure each character is a hex digit
        #
        #$ca = $macAddress.ToCharArray()
        #foreach ($c in $ca)
        #{
        #    if ($c -notmatch "[A-F0-9]")
        #    {
        #        "Error: MAC address contains non hexidecimal characters: $c"
        #        return $false
        #    }
        #}
        
        #
        # Get all the NICs on the VM. Then delete all
        # NICs of the requested type.
        #
        $nics = Get-VMNic -vm $vmName -server $hvServer -Legacy:$legacy -VMBus:(-not $legacy)
        if ($nics)
        {
            for( $i = 1; $i -lt $nics.length; $i++)
            {
                $nics[$i] | Remove-VMNic -force
            }
            $retVal = $True
        }
        else
        {
            "Error: $vmName - No NICs removed.  No $nicType NICs found."
        }
    }
}

return $retVal
