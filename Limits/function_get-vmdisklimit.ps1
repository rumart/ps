  
function Get-VMDiskLimit {
    <#
        .SYNOPSIS
            Function for getting limits on a single VMDK
        .DESCRIPTION
            The function will get the IOPS limit on a specific
            VMDK
        .LINK
            https://www.rudimartinsen.com/2018/06/29/working-with-disk-limits-in-powercli/
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
