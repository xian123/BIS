#####################################################################
#
# This test will check the time sync of guest OS with the host. It will save the state of the VM.
# It will wait for 10 mins, start the VM from saved state and will re-check the time sync.
# 
# testParams
#    HOME_DIR=d:\ica\trunk\ica
#    ipv4=
#    sshKey=
#
# now=`date "+%m/%d/%Y %H:%M:%S%p"
# returns 04/27/2012 16:10:30PM
#
#####################################################################
param ([String] $vmName, [String] $hvServer, [String] $testParams)



#####################################################################
#
# SendCommandToVM()
#
#####################################################################
function SendCommandToVM([String] $sshKey, [String] $ipv4, [string] $command)
{
    $retVal = $null

    $sshKeyPath = Resolve-Path $sshKey
    
    $dt = .\bin\plink.exe -i ${sshKeyPath} root@${ipv4} $command
    if ($?)

#    $process = Start-Process plink -ArgumentList "-i ${sshKey} root@${ipv4} ${command}" -PassThru -NoNewWindow -Wait # -redirectStandardOutput lisaOut.tmp -redirectStandardError lisaErr.tmp
#    if ($process.ExitCode -eq 0)
    {
        $retVal = $dt
    }
    else
    {
        Write-Output "Error: $vmName unable to send command to VM. Command = '$command'"
    }

    #del lisaOut.tmp -ErrorAction "SilentlyContinue"
    #del lisaErr.tmp -ErrorAction "SilentlyContinue"

    return $retVal
}


#####################################################################
#
#
#
#####################################################################
function GetUnixVMTime([String] $sshKey, [String] $ipv4)
{
    if (-not $sshKey)
    {
        return $null
    }

    if (-not $ipv4)
    {
        return $null
    }

    $unixTimeStr = $null
    $command =  'date "+%m/%d/%Y%t%T%p "'

    $unixTimeStr = SendCommandToVM ${sshKey} $ipv4 $command
    if (-not $unixTimeStr -and $unixTimeStr.Length -lt 20)
    {
        return $null
    }
    
    return $unixTimeStr
}

#####################################################################
#
#
#
#####################################################################
function GetTimeSync([String] $sshKey, [String] $ipv4)
{
    if (-not $sshKey)
    {
        return $null
    }

    if (-not $ipv4)
    {
        return $null
    }
    #
    # Get a time string from the VM, then convert the Unix time string into a .NET DateTime object
    #
    $unixTimeStr = GetUnixVMTime -sshKey "ssh\${sshKey}" -ipv4 $ipv4
    if (-not $unixTimeStr)
    {
       "Error: Unable to get date/time string from VM"
        return $False
    }

    $unixTime = [DateTime]::Parse($unixTimeStr)

    #
    # Get our time
    #
    $windowsTime = [DateTime]::Now

    #
    # Compute the timespan, then convert it to the absolute value of the total difference in seconds
    #
    $diffInSeconds = $null
    $timeSpan = $windowsTime - $unixTime
    if ($timeSpan)
    {
        $diffInSeconds = [Math]::Abs($timeSpan.TotalSeconds)
    }

    #
    # Display the data
    #
    "Windows time: $($windowsTime.ToString())"
    "Unix time: $($unixTime.ToString())"
    "Difference: $diffInSeconds"

     Write-Output "Time difference = ${diffInSeconds}" | Out-File -Append $summaryLog
     return $diffInSeconds
}


#####################################################################
#
# UpdateVmTimezoneBasedOnHost()
#
#####################################################################
function UpdateVmTimezoneBasedOnHost([String] $sshKey, [String] $ipv4)
{
	#In our test env, the usual time zone is Pacific or China Standard Time
	$command = ""
	$localTimeZone = (Get-WmiObject win32_timezone).StandardName
	if( $localTimeZone  -like "Pacific*" )
	{
		$command = "cp  /usr/share/zoneinfo/PST8PDT  /etc/localtime"
	}

	if( $localTimeZone  -like "China*" )
	{
		$command = "cp  /usr/share/zoneinfo/Asia/Shanghai  /etc/localtime"
	}
	
	# Add other time zone if it's needed
	
	if( !$command )
	{
		"Error: Time zone is not updated"
		return 1
	}

	"The command is $command"
	SendCommandToVM -sshKey "ssh\${sshKey}" -ipv4 $ipv4 -command $command
}



#####################################################################
#
# Main script body
#
#####################################################################

$retVal = $False

#
# Make sure all command line arguments were provided
#
if (-not $vmName)
{
    "Error: vmName argument is null"
    return $False
}

if (-not $hvServer)
{
    "Error: hvServer argument is null"
    return $False
}

if (-not $testParams)
{
    "Error: testParams argument is null"
    return $False
}

"timesync_savedVM.ps1"
"  vmName    = ${vmName}"
"  hvServer  = ${hvServer}"
"  testParams= ${testParams}"

#
# Parse the testParams string
#
$sshKey = $null
$ipv4 = $null
$rootDir = $null

$params = $testParams.Split(";")
foreach($p in $params)
{
    $tokens = $p.Trim().Split("=")
    if ($tokens.Length -ne 2)
    {
        # Just ignore it
        continue
    }
    
    $val = $tokens[1].Trim()
    
    switch($tokens[0].Trim().ToLower())
    {
    "sshkey"  { $sshKey = $val }
    "ipv4"    { $ipv4 = $val }
    "rootdir" { $rootDir = $val }
    default  { continue }
    }
}

#
# Make sure the required testParams were found
#
if (-not $sshKey)
{
    "Error: testParams is missing the sshKey parameter"
    return $False
}

if (-not $ipv4)
{
    "Error: testParams is missing the ipv4 parameter"
    return $False
}

"  sshKey  = ${sshKey}"
"  ipv4    = ${ipv4}"
"  rootDir = ${rootDir}"

#
# Change the working directory to where we ned to be
#
if (-not (Test-Path $rootDir))
{
    "Error: The directory `"${rootDir}`" does not exist"
    return $False
}

cd $rootDir

#
# Delete any summary.log from a previous test run, then create a new file
#
$summaryLog = "${vmName}_summary.log"
del $summaryLog -ErrorAction SilentlyContinue
Write-Output "Covers TC34" | Out-File -Append $summaryLog

#
# Load the PowerShell HyperV Library
#
<#$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
    Import-module .\HyperVLibV2Sp1\HyperV.psd1
}#>

UpdateVmTimezoneBasedOnHost -sshKey $sshKey -ipv4 $ipv4

$diffInSeconds = GetTimeSync -sshKey $sshKey -ipv4 $ipv4

$msg = "Test case FAILED"
if ($diffInSeconds -and $diffInSeconds -lt 5)
{
    $msg = "Time is properly synced"
    $retVal = $true
}

$msg


#
# Save the VM state and wait for 10 mins. 
#
#Set-VMState -Vm $vmName -Server $hvServer -State Suspended -wait -verbose
Save-VM -Name $vmName -ComputerName $hvServer -Confirm:$False
if ($? -ne "True")
{
  write-host "Error while saving the VM state"
  return $false
}

Start-Sleep -seconds 600

#
# After 10 mins start the VM and check the time sync.
#
#Set-VMState -Vm $vmName -Server $hvServer -State Running -wait -verbose
Start-VM -Name $vmName -ComputerName $hvServer -Confirm:$False
if ($? -ne "True")
{
  write-host "Error while starting the VM from saved state"
  return $false
}

$diffInSeconds = GetTimeSync -sshKey $sshKey -ipv4 $ipv4

$msg = "Test case FAILED"
if ($diffInSeconds -and $diffInSeconds -lt 5)
{
    $msg = "After start from save state, Time is properly synced"
    $retVal = $true
}

Write-Output $msg | Out-File $summaryLog

return $retVal
