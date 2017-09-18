<#
    .SYNOPSIS
        The script will remove Hosts and VMs from a DRS group if a tag is not found
    .DESCRIPTION
        The script connects to vCenter and traverses all clusters specified.
        It checks hosts and vms in a Host and a VM group and checks that these 
        have the correct tag specified.
        If the tag is not found they are removed from the DRS group
    .NOTES
        Author: Rudi Martinsen / Intility AS
        Date : 05/09-2017
        Version : 1.0.0
        Revised : 06/09-2017
        Changelog:
    .LINK
        http://www.rudimartinsen.com/2017/09/18/more-drs-group-automation/ 
    .PARAMETER VCenter
        The vCenter server to process VMs from
    .PARAMETER Logfile
        File path for a logfile to output to
#>
[CmdletBinding()]
param($vcenter,$logfile)

#Tag and Rule parameters
$vmgroup = "SQL-VM"
$hostgroup = "SQL-Host"
$vmtag = "SQL-Lic"
$hosttag = "SQL-Host"
$ruleName = "SQL-Lic"
$ruleEnable = $false


Write-Output "Connecting to vCenter $vcenter" | Out-File $logfile -Append
Connect-VIServer $vcenter | Out-Null

$clusters = Get-Cluster -server $vcenter | where {$_.name -ne "RH25-METRO" -and $_.name -ne "RH25-CL2"}
Write-Output "Found $($clusters.count) clusters" | Out-File $logfile -Append

foreach($cluster in $clusters){

    Write-Output "Processing cluster $($cluster)" | Out-File $logfile -Append
    
    $sqlHosts = @()
    $remHosts = @()
    $sqlVMs = @()
    $remVMs = @()
    
    #########
    # Hosts #
    #########
    #Retrieve DRS group and traverse all members
    $drsGroup = Get-DrsClusterGroup -Cluster $cluster -Type VMHostGroup -Name $hosttag -ErrorAction SilentlyContinue
    foreach($member in $drsgroup.Member){
        #Initiate tag existence variable
        $hostTagExists = $false
        $hostTagAssigned = $member | Get-TagAssignment -Category "Host Attributes" #| Where-Object {$_.Tag -eq $hosttag}
        
        if($hostTagAssigned){
            foreach($hosttagA in $hostTagAssigned){
                if($hosttaga.Tag.Name -eq $hosttag){
                    #Tag found, the host should remain a memeber of the group
                    $hostTagExists = $true
                }
            }
        }
        if(!$hostTagExists){
            #Tag NOT found, the host should be removed the group
            $drsGroup | Set-DrsClusterGroup -VMHost $member -Remove #-WhatIf
            $remHosts += $member
        }
    }

    if($remHosts){
        Write-Output "Removed the following Hosts:" | Out-File $logfile -Append
        Write-Output "$($remHosts)" | Out-File $logfile -Append
    }

    #########
    # VMs #
    #########
    #Retrieve DRS group and traverse all members
    $drsGroupVM = Get-DrsClusterGroup -Cluster $cluster -Type VMGroup -Name $vmtag -ErrorAction SilentlyContinue
    foreach($member in $drsGroupVM.Member){
        #Initiate tag existence variable
        $vmTagExists = $false
        $vmTagAssigned = $member | Get-TagAssignment -Category "VM Attributes" #| Where-Object {$_.Tag -eq $hosttag}

        if($vmTagAssigned){
            foreach($vmtagA in $vmTagAssigned){
                if($vmtagA.Tag.Name -eq $vmtag){
                    #Tag found, the vm should remain a memeber of the group
                    $vmTagExists = $true
                }
            }
        }
        if(!$vmTagExists){
            #Tag NOT found, the vm should be removed the group
            $drsGroupVM | Set-DrsClusterGroup -VM $member -Remove #-WhatIf
            $remVMs += $member
        }
    }

    if($remVMs){
        Write-Output "Removed the following VMs:" | Out-File $logfile -Append
        Write-Output "$($remVMs)" | Out-File $logfile -Append
    }
}

Disconnect-VIServer $vcenter -Confirm:$false