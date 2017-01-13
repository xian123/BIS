########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################

<#
.Synopsis
    Verify if the filesystem can be resized after a VHDx Hard Disk resizing.
.Description
    This is a PowerShell test case script that implements Dynamic
    Resizing of VHDX and growing the filesystem
    Ensures that the VM sees the newly attached VHDx Hard Disk and resizes the
    filesystem after the disk resizing
    Creates partitions, filesytem, mounts partitions, sees if it can perform
    Read/Write operations on the newly created partitions and deletes partitions
    A typical test case definition for this test script would look
    similar to the following:
        <test>
            <testName>ResizeVHDXGrowFS</testName>
            <testScript>SetupScripts\STOR_VHDXResizeGrowFS.ps1</testScript>
            <setupScript>SetupScripts\Add-VhdxDisk.ps1</setupScript>
            <cleanupScript>SetupScripts\Remove-VhdxDisk.ps1</cleanupScript>
            <timeout>600</timeout>
            <onError>Continue</onError>
            <testparams>
                <param>SCSI=0,0,Dynamic,512,3GB</param>
                <param>NewSize=4GB</param>
                <param>TC_COVERED=STOR-VHDx-01</param>
            </testparams>
        </test>
.Parameter vmName
    Name of the VM to attached and resize the VHDx Hard Disk.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter testParams
    Test data for this test case
.Example
    setupScripts\STOR_VHDXResizeGS.ps1 -vmName "VM_Name" -hvServer "HYPERV_SERVER" -TestParams "ipv4=255.255.255.255;sshKey=YOUR_KEY.ppk;NewSize=4GB;TC_COVERED=STOR-VHDx-01"
#>

param( [String] $vmName,
       [String] $hvServer,
       [String] $testParams
)

$sshKey     = $null
$ipv4       = $null
$newSize    = $null
$sectorSize = $null
$DefaultSize = $null
$rootDir    = $null
$TC_COVERED = $null
$TestLogDir = $null
$TestName   = $null
$vhdxDrive  = $null

#######################################################################
#
# Main script body
#
#######################################################################

#
# Make sure the required arguments were passed
#
if (-not $vmName)
{
    "Error: no VMName was specified"
    return $False
}

if (-not $hvServer)
{
    "Error: No hvServer was specified"
    return $False
}

if (-not $testParams)
{
    "Error: No test parameters specified"
    return $False
}

#
# Debug - display the test parameters so they are captured in the log file
#
Write-Output "TestParams : '${testParams}'"

$summaryLog  = "${vmName}_summary.log"
Del $summaryLog -ErrorAction SilentlyContinue

#
# Parse the test parameters
#
$params = $testParams.TrimEnd(";").Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    $value = $fields[1].Trim()

    switch ($fields[0].Trim())
    {
    "SSHKey"    { $sshKey  = $fields[1].Trim() }
    "ipv4"      { $ipv4    = $fields[1].Trim() }
    "newSize"   { $newSize = $fields[1].Trim() }
    "sectorSize"   { $sectorSize = $fields[1].Trim() }
    "DefaultSize"   { $DefaultSize = $fields[1].Trim() }
    "rootDIR"   { $rootDir = $fields[1].Trim() }
    "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
    "TestLogDir" { $TestLogDir = $fields[1].Trim() }
    "TestName"   { $TestName = $fields[1].Trim() }
    default     {}  # unknown param - just ignore it
    }
}

if (-not $rootDir)
{
    "Warn : no rootdir was specified"
}
else
{
    cd $rootDir
}

# Source STOR_VHDXResize_Utils.ps1
if (Test-Path ".\setupScripts\STOR_VHDXResize_Utils.ps1")
{
    . .\setupScripts\STOR_VHDXResize_Utils.ps1
}
else
{
    "Error: Could not find setupScripts\STOR_VHDXResize_Utils.ps1"
    return $false
}

Write-Output "Covers: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

#
# Convert the new size
#
$newVhdxSize = ConvertStringToUInt64 $newSize

#
# Make sure the VM has a SCSI 0 controller, and that
# Lun 0 on the controller has a .vhdx file attached.
#
"Info : Check if VM ${vmName} has a SCSI 0 Lun 0 drive"
$vhdxName = $vmName + "-" + $DefaultSize + "-" + $sectorSize + "-test"
$vhdxDisks = Get-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer

foreach ($vhdx in $vhdxDisks)
{
    $vhdxPath = $vhdx.Path
    if ($vhdxPath.Contains($vhdxName))
    {
        $vhdxDrive = Get-VMHardDiskDrive -VMName $vmName -Controllertype SCSI -ControllerNumber $vhdx.ControllerNumber -ControllerLocation $vhdx.ControllerLocation -ComputerName $hvServer -ErrorAction SilentlyContinue
    }
}
if (-not $vhdxDrive)
{
    "Error: VM ${vmName} does not have a SCSI 0 Lun 0 drive"
    $error[0].Exception.Message
    return $False
}

"Info : Check if the virtual disk file exists"
$vhdPath = $vhdxDrive.Path
$vhdxInfo = GetRemoteFileInfo $vhdPath $hvServer
if (-not $vhdxInfo)
{
    "Error: The vhdx file (${vhdPath} does not exist on server ${hvServer}"
    return $False
}

"Info : Verify the file is a .vhdx"
if (-not $vhdPath.EndsWith(".vhdx") -and -not $vhdPath.EndsWith(".avhdx"))
{
    "Error: SCSI 0 Lun 0 virtual disk is not a .vhdx file."
    "       Path = ${vhdPath}"
    return $False
}

#
# Make sure there is sufficient disk space to grow the VHDX to the specified size
#
$deviceID = $vhdxInfo.Drive
$diskInfo = Get-WmiObject -Query "SELECT * FROM Win32_LogicalDisk Where DeviceID = '${deviceID}'" -ComputerName $hvServer
if (-not $diskInfo)
{
    "Error: Unable to collect information on drive ${deviceID}"
    return $False
}

if ($diskInfo.FreeSpace -le $newVhdxSize + 10MB)
{
    "Error: Insufficent disk free space"
    "       This test case requires ${newSize} free"
    "       Current free space is $($diskInfo.FreeSpace)"
    return $False
}

#
# Make sure if we can perform Read/Write operations on the guest VM
#
$guest_script = "STOR_VHDXResize_PartitionDisk"

$sts = RunRemoteScriptCheckResult $guest_script

if (-not $($sts[-1]))
{
  "Error: Running '${guest_script}'script failed on VM. check VM logs , exiting test case execution "
  return $False
}

"Info : Resizing the VHDX to ${newSize}"
Resize-VHD -Path $vhdPath -SizeBytes ($newVhdxSize) -ComputerName $hvServer -ErrorAction SilentlyContinue
if (-not $?)
{
   "Error: Unable to grow VHDX file '${vhdPath}"
   return $False
}


#
# Let system have some time for the volume change to be indicated
#
$sleepTime = 180
Start-Sleep -s $sleepTime

$RetryCounts = 0
$Retrylimits = 10

$diskSize = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "diskinfo -v da1 | grep bytes | cut -f 1 -d '#'"  2>$null
while (-not $? -and $RetryCounts -lt $Retrylimits)
{
	$RetryCounts ++
	Start-Sleep -s 10
	"Attempt $RetryCounts/$Retrylimits : Determine disk size from within the guest"
	$diskSize = .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "diskinfo -v da1 | grep bytes | cut -f 1 -d '#'"   2>$null
}
if($RetryCounts -ge $Retrylimits)
{
	"Error: Unable to determine disk size from within the guest after growing the VHDX"
	return $False
}

if ($diskSize.Trim() -ne $newVhdxSize)
{
    "Error: VM ${vmName} sees a disk size of ${diskSize}, not the expected size of ${newVhdxSize}"
    return $False
}

#
# Make sure if we can perform Read/Write operations on the guest VM
#
$guest_script = "STOR_VHDXResize_GrowFSAfterResize"

$sts = RunRemoteScriptCheckResult $guest_script
if (-not $($sts[-1]))
{
  "Error: Running '${guest_script}'script failed on VM. check VM logs , exiting test case execution "
  return $False
}

"Info : The guest sees the new size after resizing ($diskSize)"
"Info : VHDx Resize - ${TC_COVERED} is Done"

return $True