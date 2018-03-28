<#
    .SYNOPSIS
        The script will create DRS groups and rules for SQL tagged Hosts and VMs
    .DESCRIPTION
        The script connects to vCenter and traverses all clusters specified.
        It checks for Hosts in the cluster with a SQL tag and if found creates a 
        DRS Host group with the hosts found.

        It checks each VM for the existence of a SQL tag and if found creates a
        DRS VM group with the vms found

        If host and vm groups are found or created the script will check for 
        the existence of a DRS rule which specifies that the VM group should run
        its VMs on the Host group.
        It the rule is not found it will be created
    .NOTES
        Author: Rudi Martinsen / Intility AS
        Date : 05/09-2017
        Version : 1.1.2
        Revised : 28/03-2018
        Changelog:
        1.1.2 -- Removed unused variables
        1.1.1 -- Added link
        1.1.0 -- Added functionality for writing to the Notes field on VMs
    .LINK        
        http://www.rudimartinsen.com/2017/09/08/automating-drs-groups-with-powercli/
    .PARAMETER VCenter
        The vCenter server to process VMs from
    .PARAMETER Logfile
        File path for a logfile to output to
#>
[CmdletBinding()]
param($vcenter,$logfile)

#Tag and Rule parameters
$vmtag = "SQL-Lic"
$hosttag = "SQL-Host"
$ruleName = "SQL-Lic"
$ruleEnable = $false


Write-Output "Connecting to vCenter $vcenter" | Out-File $logfile -Append
Connect-VIServer $vcenter | Out-Null

$clusters = Get-Cluster -server $vcenter
Write-Output "Found $($clusters.count) clusters" | Out-File $logfile -Append

foreach($cluster in $clusters){
    Write-Output "Processing cluster $($cluster)" | Out-File $logfile -Append
    $sqlHosts = @()
    $sqlVMs = @()

    #Initiate existence variables
    $vmTagExists = $false
    $hostGroupExists = $false
    $vmGroupExists = $false

    #Check if DRS groups exists
    $drsHostGroup = Get-DrsClusterGroup -Cluster $cluster -Type VMHostGroup -Name $hosttag -ErrorAction SilentlyContinue
    $drsVMGroup = Get-DrsClusterGroup -Cluster $cluster -Type VMGroup -Name $vmtag -ErrorAction SilentlyContinue
    if($drsHostGroup){
        Write-Verbose "DRS group for SQL hosts found"
        $hostGroupExists = $true
    }
    if($drsVMGroup){
        Write-Verbose "DRS group for SQL hosts found"
        $vmGroupExists = $true
    }

    #########
    # Hosts #
    #########
    #Retrieve Connected hosts and check if the tag exists
    $vmhosts = $cluster | Get-VMHost -State Connected
    foreach($vmhost in $vmhosts){
        $hostTagAssigned = $vmhost | Get-TagAssignment -Category "Host Attributes"
        if($hostTagAssigned){
            foreach($hosttagA in $hostTagAssigned){
                if($hosttaga.Tag.Name -eq $hosttag){
                    $sqlHosts += $vmhost
                    $hostTagExists = $true
                }
            }
        }
    }

    #Create SQL-Host Group if tag is found and group is not found
    if(!$hostGroupExists -and $hostTagExists -and $sqlHosts -ne $null){
        #Create DRS group
        Write-Verbose "Creating DRS Host group"
        New-DrsClusterGroup -Name $hosttag -Cluster $cluster -VMHost $sqlHosts #-WhatIf
        $drsHostGroup = Get-DrsClusterGroup -Cluster $cluster -Type VMHostGroup -Name $hosttag -ErrorAction SilentlyContinue
        if($drsHostGroup){
            $hostGroupExists = $true
        }
    }
    else{
        #Write-Verbose "Host tag doesn't exist, no need for the group."
    }

    #Check if Hosts are a member of the DRS group
    if($hostGroupExists -and $hostTagExists){
        foreach($sqlHost in $sqlHosts){
            if(!$drsHostGroup.Member.Contains($sqlHost)){
                #Host is NOT a member, adding
                $drsHostGroup | Set-DrsClusterGroup -Add -VMHost $sqlhost #-WhatIf
            }
        }
    }

    #########
    # VMs #
    #########
    #Retrieve vms and check if the tag exists
    $vms = $cluster | Get-VM
    foreach($vm in $vms){
        $vmTagAssigned = $vm | Get-TagAssignment -Category "VM Attributes"
        if($vmTagAssigned){
            foreach($vmtagA in $vmTagAssigned){
                if($vmtagA.Tag.Name -eq $vmtag){
                    $sqlVMs += $vm
                    $vmTagExists = $true
                    if($vm.Notes -notlike "*sql*"){
                        if($vm.notes -eq $null -or $vm.notes -eq ""){
                            Set-VM $vm -Notes $vmtag -Confirm:$false
                        }
                        else{
                            $newnote = $vm.Notes + ";$vmtag"
                            Set-VM -VM $vm -Notes $newnote -Confirm:$false
                        }
                    }
                }
            }
        }
    }

    #SQL VMs found but no SQL hosts found. Should this be reported?
    if($vmTagExists -and !$hostTagExists){
        Write-Verbose "VMs with SQL tag exists, but there are no hosts with a SQL tag!"
    }

    #Create SQL VM Group if tag is found and group is not found
    if(!$vmGroupExists -and $vmTagExists -and $sqlHosts -ne $null){
        Write-Verbose "Creating DRS VM group"
        New-DrsClusterGroup -Name $vmtag -Cluster $cluster -VM $sqlVMs #-WhatIf
        $drsVMGroup = Get-DrsClusterGroup -Cluster $cluster -Type VMGroup -Name $vmtag -ErrorAction SilentlyContinue
        if($drsVMGroup){
            $vmGroupExists = $true
        }
    }
    else{
        #Write-Verbose "VM tag doesn't exist, no need for the group."
    }

    #Check if VM are a member of the DRS group
    if($vmGroupExists -and $vmTagExists){
        foreach($sqlVM in $sqlVMs){
            if(!$drsVMGroup.Member.Contains($sqlVM)){
                #VM is NOT a member, adding
                $drsVMGroup | Set-DrsClusterGroup -Add -VM $sqlVM #-WhatIf
            }
        }
    }


    ############
    # DRS Rule #
    ############
    #Check DRS Rule
    if($hostGroupExists -and $vmGroupExists){
        $drsRules = Get-DrsVMHostRule -Cluster $cluster -Type ShouldRunOn -VMHostGroup $drsHostGroup -VMGroup $drsVMGroup
        if(!$drsRules){
            #Rule doesn't exist
            Write-Verbose "Creating DRS rule"
            New-DrsVMHostRule -Name $ruleName -Cluster $cluster -VMHostGroup $drsHostGroup -VMGroup $drsVMGroup -Type MustRunOn -Enabled:$ruleEnable #-WhatIf
        }
    }

}
Disconnect-VIServer $vcenter -Confirm:$false