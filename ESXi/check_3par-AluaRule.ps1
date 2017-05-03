<#
    .SYNOPSIS
        Script to check for the existence of a 3PAR ALUA rule on ESXi hosts
    .DESCRIPTION
        The script connects to a vCenter to get a list of ESXi hosts and then
        connects to each of these to create an ESXCLI object which is used
        to check for the existence of a custom 3PAR VMW_SATP_ALUA rule
    .NOTES
        Author: Rudi Martinsen / Intility AS
        Created: 02/05-2017
        Version: 1.0.0
        Revised: 
    .LINK
        #Add custom SATP claimrule for HP 3PAR to ESXi - vcloudnine.de
        https://www.vcloudnine.de/add-custom-satp-claimrule-for-hp-3par-to-vmware-esxi/
    .LINK
        #Automating the 3PAR ESXi SATP Rule Creation - virtuallyhyper.com
        http://virtuallyhyper.com/2013/10/automating-3par-satp-rule-creation-powercli/
    .PARAMETER VCenter
        VCenter to connet to
    .PARAMETER Cluster
        Cluster to get hosts from
    .PARAMETER RootPass
        Password of ESXi Root user
#>
param ($VCenter,$Cluster)

$RootPass = (Read-Host -Prompt "Please type password of ESXi Root user" -AsSecureString)

Connect-I2VCenter $VCenter

if($Cluster){
    $vmhosts = Get-Cluster $Cluster | Get-VMHost -Server $vcenter | Where-Object {$_.PowerState -eq "PoweredOn"}
}
else{
    $vmhosts = Get-VMHost -Server $vcenter | Where-Object {$_.PowerState -eq "PoweredOn"}
}
Disconnect-VIServer $vcenter -Confirm:$false

#$RootPass = "Password here"
$Pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($RootPass))

$outTbl = @()

foreach($vmhost in $vmhosts){

    Connect-I2ESXHost $vmhost -Username root -Password $Pass | Out-Null
    $esxcli = Get-EsxCli -V2 -VMHost $vmhost.Name
    $rule = $esxcli.storage.nmp.satp.rule.list.Invoke() | where {$_.description -like "*3par*"} 
    Disconnect-VIServer $vmhost.Name -Confirm:$false
    
    $output = [PSCustomObject]@{
        HostName = $vmhost.name;
        RuleName = $rule.Name;
        PSP = $rule.DefaultPSP;
        RR_IOPS = $rule.PSPOptions;
        ClaimOptions = $rule.ClaimOptions;
    }
    $outTbl += $output

    #Command for setting the rule, could be added if it not exists
    #$esxcli.storage.nmp.satp.rule.add($null,"tpgs_on","HP 3Par Custom Rule",$null,$null,$null,"VV",$null,"VMW_PSP_RR","iops=1","VMW_SATP_ALUA",$null,$null,"3PARdata")
    
}

$outTbl | Format-Table
