
function Get-VMLimits{
    <#
        .SYNOPSIS
            Function for retrieving the IO limits set on a VM
        .DESCRIPTION
            The function will retrieve the Throughput limit (IOPS) set on
            the disks of a VM.
            A connection to the vCenter instance where the VM is running is needed.
        .LINK
            https://www.rudimartinsen.com/2018/06/29/working-with-disk-limits-in-powercli/
        .NOTES
            Info
            Author : Rudi Martinsen / Intility AS
            Date : 28/06-2018
            Version : 1.0.0
            Revised : 
            Changelog : 
        .PARAMETER Name
            Specifies the VM to retrieve limits for
        .EXAMPLE
            Get-VMLimits -Name vm001
            This will retrieve the IO limits set on the VM "vm001" and
            output to screen
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [Alias('VM')]
        [string]
        $Name
    )
    
    $vmObj = Get-VM -Name $Name

    if(!$vmObj){
        Write-Error "Couldn't connect to virtual machine $Computername"
        break
    }

    if ($vmObj.Count -gt 1) {
        Write-Verbose -Message "Multiple VMs found"
    }
    $outputTbl = @()
    foreach ($v in $vmObj){

        $diskLimits = $v | Get-VMResourceConfiguration | Select-Object -ExpandProperty DiskResourceConfiguration
        $disks = $v | Get-HardDisk
        foreach($disk in $disks){
            $diskLimit = $diskLimits | Where-Object {$_.key -eq $disk.ExtensionData.Key}
            $o = [pscustomobject]@{
                VM = $v.Name
                Name = $disk.Name
                Key = $disk.ExtensionData.Key
                IOPSLimit = $diskLimit.DiskLimitIOPerSecond
            }
            $outputTbl += $o
        }

    }#end foreach VM

    return $outputTbl
}