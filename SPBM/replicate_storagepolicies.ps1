<#
    .SYNOPSIS
        Script for replicating Storage Policies to multiple vCenters
    .DESCRIPTION
        The script retrieves Storage policies based on the names you 
        specifies and replicates them to multiple vCenter servers
        The first vCenter in the vCenters variable will be the "master"
        and the following vCenters will be the ones to replicate to
    .NOTES
        Author: Rudi Martinsen / Intility AS
        Created: 16/03-2018
        Version 0.1.0
        Revised: 
        Changelog:
#>
$vCenters = "vcenter-1","vcenter-2","vcenter-3"

Connect-VIServer $vCenters -NotDefault

$policies = Get-SpbmStoragePolicy -Server $vCenters[0] | where {$_.Name -like "VMDK-*" -or $_.name -like "VM-*"}

$tempLocation = "D:\temp\policies"
if(!(Test-Path $tempLocation)){
    New-Item -ItemType Directory -Path $tempLocation
}

foreach($policy in $policies){
    $policyName = $policy.Name
    $description = $policy.Description

    $filename = "$tempLocation\$policyname.xml"
    
    $policy | Export-SpbmStoragePolicy -FilePath $filename
    
    for($i = 1;$i -le $vcenters.count;$i++){
        
        if(!(Get-SpbmStoragePolicy -Name $policyName -Server $vcenters[$i] -ErrorAction SilentlyContinue)){
            Import-SpbmStoragePolicy -FilePath $filename -Name $policyName -Server $vcenters[$i] -Description $Description
        }
        else{
            Write-Warning "Policy already exists"
        }
    }
}

