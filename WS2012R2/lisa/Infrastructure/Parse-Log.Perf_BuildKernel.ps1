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
    Parse the network bandwidth data from the BuildKernel test log.

.Description
    Parse the network bandwidth data from the BuildKernel test log.
    
.Parameter LogFolder
    The LISA log folder. 

.Parameter XMLFileName
    The LISA XML file. 

.Parameter LisaInfraFolder
    The LISA Infrastructure folder. This is used to located the LisaRecorder.exe when running by Start-Process 

.Exmple
    Parse-Log.Perf_BuildKernel.ps1 C:\Lisa\TestResults D:\Lisa\XML\Perf_BuildKernel.xml D:\Lisa\Infrastructure

#>

param( [string]$LogFolder, [string]$XMLFileName, [string]$LisaInfraFolder )

#----------------------------------------------------------------------------
# Print running information
#----------------------------------------------------------------------------
Write-Host "Running [Parse-Log.Perf_BuildKernel.ps1]..." -foregroundcolor cyan
Write-Host "`$LogFolder        = $LogFolder" 
Write-Host "`$XMLFileName      = $XMLFileName" 
Write-Host "`$LisaInfraFolder  = $LisaInfraFolder" 

#----------------------------------------------------------------------------
# Verify required parameters
#----------------------------------------------------------------------------
if ($LogFolder -eq $null -or $LogFolder -eq "")
{
    Throw "Parameter LogFolder is required."
}

# Check the XML file provided
if ($XMLFileName -eq $null -or $XMLFileName -eq "")
{
    Throw "Parameter XMLFileName is required."
}
else
{
    if (! (test-path $XMLFileName))
    {
        write-host -f Red "Error: XML config file '$XMLFileName' does not exist."
        Throw "Parameter XmlFilename is required."
    }
}

$xmlConfig = [xml] (Get-Content -Path $xmlFilename)
if ($null -eq $xmlConfig)
{
    write-host -f Red "Error: Unable to parse the .xml file"
    return $false
}

if ($LisaInfraFolder -eq $null -or $LisaInfraFolder -eq "")
{
    Throw "Parameter LisaInfraFolder is required."
}

#----------------------------------------------------------------------------
# The log file pattern. The log is produced by the BuildKernel tool
#----------------------------------------------------------------------------
$BuildKernelLofFiles = "*_Perf_BuildKernel_*.log"

#----------------------------------------------------------------------------
# Read the BuildKernel log file
#----------------------------------------------------------------------------

#Function to parse time from string
    #result example: 
    #real	4m32.412s
    #user	0m2.388s
    #sys	0m5.832s
function ParseTimeInSec([string] $rawTime)
{
    $posTab = $rawTime.IndexOf("	")
    $timeString = $rawTime.Substring($posTab + 1)
    
    $timeString = $timeString.Trim()
    $posM = $timeString.IndexOf("m")
    $posS = $timeString.IndexOf("s")

    $timeM = $timeString.Substring(0, $posM)
    $timeS = $timeString.Substring($posM + 1, $posS - $posM -1)
    return  [int]$timeM * 60 + [double]$timeS
}

$icaLogs = Get-ChildItem "$LogFolder\$BuildKernelLofFiles" -Recurse
Write-Host "Number of Log files found: "
Write-Host $icaLogs.Count

if($icaLogs.Count -eq 0)
{
    return -1
}

$realTimeInSec = 0
$userTimeInSec = 0
$sysTimeInSec = 0
foreach ($logFile  in $icaLogs)
{
    Write-Host "One log file has been found: $logFile" 
    
    #we should find the result in the last 4 line
    #result example: 
    #real	4m32.412s
    #user	0m2.388s
    #sys	0m5.832s
    $resultFound = $false
    $iTry=1
    while (($resultFound -eq $false) -and ($iTry -lt 4))
    {
        $line = (Get-Content $logFile)[-1* $iTry]
        Write-Host $line

        $iTry++
        $line = $line.Trim()
        if ($line.Trim() -eq "")
        {
            continue
        }
        elseif ($line.StartsWith("sys") -eq $true)
        {
            $sysTimeInSec += ParseTimeInSec($line)
            Write-Host "sys time parsed in seconds: $sysTimeInSec" 
            continue
        }
        elseif ($line.StartsWith("user") -eq $true)
        {
            $userTimeInSec += ParseTimeInSec($line)
            Write-Host "user time parsed in seconds: $userTimeInSec" 
            continue
        }
        elseif ($line.StartsWith("real") -eq $true)
        {
            $realTimeInSec += ParseTimeInSec($line)
            Write-Host "real time parsed in seconds: $realTimeInSec" 
            continue
        }
        else
        {
            break
        }
    }
}

#----------------------------------------------------------------------------
# Read the test summary log file
#----------------------------------------------------------------------------
$TestSummaryLogPattern = "$LogFolder\*\*_summary.log"
# Source the library functions
. $LisaInfraFolder\LoggerFunctions.ps1 | out-null

$kernelRelease = GetValueFromLog $TestSummaryLogPattern "KernelRelease"
$processorCount = GetValueFromLog $TestSummaryLogPattern "ProcessorCount"
if ($kernelRelease -eq [string]::Empty)
{ 
    $kernelRelease = "Unknown"
}
if ($processorCount -eq [string]::Empty)
{ 
    $processorCount = "0"
}

#----------------------------------------------------------------------------
# Read BuildKernel configuration from XML file
#----------------------------------------------------------------------------
$VMName = [string]::Empty
$newLinuxKernel = [string]::Empty

$numberOfVMs = $xmlConfig.config.VMs.ChildNodes.Count
Write-Host "Number of VMs defined in the XML file: $numberOfVMs"
if ($numberOfVMs -eq 0)
{
    Throw "No VM is defined in the LISA XML file."
}
elseif ($numberOfVMs -gt 1)
{
    foreach($node in $xmlConfig.config.VMs.ChildNodes)
    {
        if (($node.role -eq $null) -or ($node.role.ToLower() -ne "nonsut"))
        {
            #just use the 1st SUT VM name
            $VMName = $node.vmName
            break
        }
    }
}
else
{
    $VMName = $xmlConfig.config.VMs.VM.VMName
}
if ($VMName -eq [string]::Empty)
{
    Write-Host "!!! No VM is found from the LISA XML file."
}

foreach($param in $xmlConfig.config.testCases.test.testParams.ChildNodes)
{
    $paramText = $param.InnerText
    if ($paramText.ToUpper().StartsWith("KERNELVERSION="))
    {
        $newLinuxKernel = $paramText.Split('=')[1]
    }
}

Write-Host "VMName: " $VMName
Write-Host "KernelVersion" $newLinuxKernel

#----------------------------------------------------------------------------
# Call LisaRecorder to log data into database
#----------------------------------------------------------------------------
$LisaRecorder = "$LisaInfraFolder\LisaLogger\LisaRecorder.exe"
$params = "LisPerfTest_BuildKernel"
$params = $params+" "+"hostos:`"" + (Get-WmiObject -class Win32_OperatingSystem).Caption + "`""
$params = $params+" "+"hostname:`"" + "$env:computername.$env:userdnsdomain" + "`""
$params = $params+" "+"guestos:`"" + $kernelRelease + "`""
$params = $params+" "+"linuxdistro:`"" + "$VMName" + "`""
$params = $params+" "+"testcasename:`"" + "Perf_BuildKernel" + "`""
$params = $params+" "+"newlinuxkernel:`"" + "$newLinuxKernel" + "`""
$params = $params+" "+"realtimeinsec:`"" + $realTimeInSec + "`""
$params = $params+" "+"usertimeinsec:`"" + $userTimeInSec + "`""
$params = $params+" "+"systimeinsec:`"" + $sysTimeInSec + "`""
$params = $params+" "+"processorcount:`"" + $processorCount + "`""


Write-Host "Executing LisaRecorder to record test result into database"
Write-Host $params

$result = Start-Process -FilePath $LisaRecorder -Wait -ArgumentList $params -PassThru -RedirectStandardOutput "$LogFolder\LisaRecorderOutput.log" -RedirectStandardError "$LogFolder\LisaRecorderError.log"
if ($result.ExitCode -eq 0)
{
    Write-Host "Executing LisaRecorder finished with Success."
}
else
{
    Write-Host "Executing LisaRecorder failed with exit code: " $result.ExitCode
}

return $result.ExitCode

