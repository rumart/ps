param($VCenter,$Cluster,$LogFile)
<#
    .SYNOPSIS
        The script will set VM disk limits based on the configured Storage Policy
    .DESCRIPTION
        The script checks and sets VM disk limits on all VMs from the Storage Policies
        configured on the disk.
        
        VMs are filtered against a list of VMs that should NOT be touched
    .LINK
        https://www.rudimartinsen.com/2018/07/02/automating-disk-limits-in-vsphere/
    .NOTES
        Author: Rudi Martinsen / Intility AS
        Date : 29/06-2018
        Version : 1.0.0
        Revised : 
        Changelog:
    .PARAMETER VCenter
        The vCenter server to process VMs from
    .PARAMETER Cluster
        The cluster to process VMs from
    .PARAMETER LogFile
        The logfile to write script output to
#>
#############
# Functions #
#############
function Write-Log {
    <#
        .SYNOPSIS
            The function enables scripts to write to a logfile
        .DESCRIPTION
            The function accepts two parameters, logfile and message
            Logfile parameter defaults to c:\temp\logfile.log if not passed
            The function will check if the logfile already exists and will append if found
        .NOTES
            Info
            Author : Rudi Martinsen -- rudi.martinsen@gmail.com
            Date : 08/05-2012
            Version : 3
            Revised : 05/02-2013
        .PARAMETER logfile
            The path to logfile
            Defaults to c:\temp\logfile.log if not passed
        .PARAMETER message
            The message to be written to the logfile. Current date&time is
            included in the message by default
        .EXAMPLE
            Write-Log -logfile c:\script\logfile.txt -message "Message 123"
            This will create a logfile at the specified path with the given message
        .EXAMPLE
            Write-Log -message "Message 123"
            This will create a logfile at the default path (c:\temp\logfile.log) with
            the given message
    #>
    param(
        $logfile = "C:\temp\logfile.log",
        [string]$message
    )

    $date = Get-Date -Format "yyyy.MM.dd HH:mm:ss"

    if(Test-Path $logfile){
        $loginit = $true
    }
    else{
        $loginit = $false
$logheader = @"
**********************************
Logfile : $logfile
Created : $(get-date)
**********************************
"@
}

    if(!$loginit){
        New-Item -ItemType File -Path $logfile
        write $logheader | Out-File $logfile -Encoding unicode
        write "$date : $message" | Out-File $logfile -Encoding unicode -Append
    }
    else{
        write "$date : $message" | Out-File $logfile -Encoding unicode -Append
    }

}#end function Write-Log
    
function Get-VMDiskLimit {
    <#
        .SYNOPSIS
            Function for getting limits on a single VMDK
        .DESCRIPTION
            The function will get the IOPS limit on a specific
            VMDK
        .NOTES
            Info
            Author : Rudi Martinsen / Intility AS
            Date : 24/02-2018
            Version : 0.1.1
            Revised : 24/02-2018
            Changelog:
            0.1.1 -- Added VM name to output
        .PARAMETER Harddisk
            VMDK to get limits from
        .EXAMPLE
            Get-VMDiskLimit -Harddisk $disk
            Gets the limits on a VMDK
    #>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName="vmdk")]
        [Alias("VMDK")]
        [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.FlatHardDisk]
        $Harddisk
    )

    $Harddisk.Parent | Get-VMResourceConfiguration | Select-Object -ExpandProperty DiskResourceConfiguration | Where-Object {$_.key -eq $Harddisk.ExtensionData.key} | Select-Object @{l="VM";e={$Harddisk.Parent.Name}},@{l="Label";e={$Harddisk.Name}},@{l="IOPSLimit";e={$_.DiskLimitIOPerSecond}}

}

function Set-VMDiskLimit {
    <#
        .SYNOPSIS
            Function for setting limits on a single VMDK
        .DESCRIPTION
            The function will get the IOPS limit on a specific
            VMDK
        .NOTES
            Info
            Author : Rudi Martinsen / Intility AS
            Date : 24/02-2018
            Version : 1.0.0
            Revised : 24/02-2018
            Changelog:
        .PARAMETER Harddisk
            VMDK to set limits on
        .PARAMETER IOPSLimit
            The IOPSLimit to set
        .EXAMPLE
            Set-VMDiskLimit -Harddisk $disk -IOPSLimit 500
            Sets the IOPS limit on the VMDK to 500
    #>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName="vmdk")]
        [Alias("VMDK")]
        [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.FlatHardDisk]
        $Harddisk,
        [Parameter(Mandatory=$true)]
        [Alias("Limit")]
        [int]
        $IOPSLimit
    )

    $result = Get-VMResourceConfiguration -VM $Harddisk.parent | Set-VMResourceConfiguration -Disk $Harddisk -DiskLimitIOPerSecond $IOPSLimit
    $result.DiskResourceConfiguration | Where-Object {$_.key -eq $Harddisk.ExtensionData.Key}

}


$scriptstart = Get-Date
Write-Log -logfile $logfile -message "Script start"

Write-Log -logfile $logfile -message "Connecting to vCenter"
$vc_conn = Connect-VIServer $vcenter
if($vc_conn){
    Write-Log -logfile $logfile -message "Connected to vCenter $vcenter with sessionID: $($vc_conn.SessionId)"
}
else{
    Write-Log -logfile $logfile -message "ERROR -- Couldn't connect to vCenter. Exiting"
    break
}

$policies2check = "NoRep 500 IOPS"

$limitsSet = 0

if($cluster){
    $disks = Get-Cluster $cluster | Get-VM | Get-HardDisk
}
else{
    $disks = Get-VM | Get-HardDisk
}

Write-Log -logfile $logfile -message "Found $($vms.count) VMs to process"

foreach($disk in $disks){
    $lapstart = Get-Date
    Clear-Variable limit,expectedLimit -ErrorAction SilentlyContinue
    Write-Log -logfile $logfile -message "Processing VMDK $($disk.name) for VM $($disk.Parent.Name)"
    $diskPolicy = Get-SpbmEntityConfiguration -HardDisk $disk
    if($diskPolicy.StoragePolicy){
        if($diskPolicy.StoragePolicy.Name -in $policies2check){
            $set = $false
            $expectedLimit = $diskPolicy.StoragePolicy.Name.Split(" ")[1]
            Write-Log -logfile $logfile -message "Checking VMDK limits"
            
            $limit = Get-VMDiskLimit -Harddisk $disk | Select-Object -ExpandProperty IOPSLimit
            if($limit -gt 0 -and $limit -ne $expectedLimit){
                #Limit is set, but is not corresponding to expected limit
                Write-Log -logfile $logfile -message "Limit is set to $limit, but is not corresponding to expected limit of $expectedlimit"
                $set = $true
            }
            elseif($limit -eq $expectedlimit){
                #Limit is set and corresponds to expected limit. Nothing to do...
                Write-Log -logfile $logfile -message "Limit is set and corresponds to expected limit"
            }
            else{
                #Limit is not set or couldn't be retrieved!
                Write-Log -logfile $logfile -message "Limit is not set or couldn't be retrieved!"
                $set = $true
            }
        }
    }

    #Policy and limits are checked. If the $set variable is $true we will carry on with changing the limit
    if($set){
        Write-Log -logfile $logfile -message "Setting limit on disk $($disk.name) to $expectedlimit"
        $result = Set-VMDiskLimit -Harddisk $disk -IOPSLimit $expectedLimit
        $limitsSet++

        #Do a check on the limit set
        if($result.DiskLimitIOPerSecond -ne $expectedLimit){
            Write-Log -logfile $logfile -message "ERROR -- Limit is still not set to the expected value"
        }
    }
    
    Write-Log -logfile $logfile -message "Finished processing disk"
    $lapend = Get-Date
    $lapSpan = New-TimeSpan -Start $lapstart -End $lapend
    Write-Log -logfile $logfile -message "Disk processed in $($lapSpan.TotalSeconds) seconds"

}
    
Write-Log -logfile $logfile -message "All disks processed. Limits were set on $limitsSet disk(s)"

$scriptEnd = Get-Date
$scriptSpan = New-TimeSpan -Start $scriptstart -End $scriptEnd
Write-Log -logfile $logfile -message "Script processed in $($scriptSpan.TotalMinutes) minutes"
