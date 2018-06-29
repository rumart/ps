
function Set-VMDiskLimit {
    <#
        .SYNOPSIS
            Function for setting limits on a single VMDK
        .DESCRIPTION
            The function will get the IOPS limit on a specific
            VMDK
        .LINK
            https://www.rudimartinsen.com/2018/06/29/working-with-disk-limits-in-powercli/
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
    $result.DiskResourceConfiguration | Where-Object {$_.key -eq $Harddisk.ExtensionData.Key} #| Select-Object @{l="VM";e={$Harddisk.Parent.Name}},@{l="Label";e={$Harddisk.Name}},@{l="IOPSLimit";e={$_.DiskLimitIOPerSecond}}

}