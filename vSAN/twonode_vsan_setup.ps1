<#
    .SYNOPSIS
        Script for automated setup of two node VSAN
    .DESCRIPTION
        The script creates a new cluster, adds
        the hosts, deploys the VSAN witness host, configures
        the network settings and standard ESXi settings for hosts.

        The script is purpose built for a customer case and might
        require some changes to work in other environments.
        The location parameter is key in determining the correct name
        for clusters and hosts.
    .NOTES
        Author: Rudi Martinsen / Intility AS
        Created: 04/10-2018
        Version: 1.1.0
        Revised: 25/10-2018
        Changelog:
        1.1.0 -- Fixed teaming policy
        1.0.0 -- Finished setup of VSAN cluster with fault domains, witness host etc
        0.3.0 -- Parameterized names from loc.code
    .LINK
        https://www.rudimartinsen.com/2018/12/31/automating-two-node-vsan-cluster-setup/
    .LINK
        https://www.jasemccarty.com/blog/deploy2node-ps1/
    .PARAMETER LocationCode
        The location code of the new location, used to determine name for Cluster and hosts
    .PARAMETER WitnessIP
        IP address for the witness host
    .PARAMETER WitnessGW
        GW for the Witness Host
#>
param(
    [cmdletbinding()]
    [Parameter(Mandatory=$true)]
    $LocationCode,
    [Parameter(Mandatory=$true)]
    $WitnessIP,
    [Parameter(Mandatory=$false)]
    $WitnessGW
)

Function runGuestOpInESXiVM() {
	param(
		$vm_moref,
		$guest_username = "root", 
		$guest_password = "password",
		$guest_command_path,
		$guest_command_args
	)
	
	# Guest Ops Managers
	$guestOpMgr = Get-View $session.ExtensionData.Content.GuestOperationsManager
	$authMgr = Get-View $guestOpMgr.AuthManager
	$procMgr = Get-View $guestOpMgr.processManager
	
	# Create Auth Session Object
	$auth = New-Object VMware.Vim.NamePasswordAuthentication
	$auth.username = $guest_username
	$auth.password = $guest_password
	$auth.InteractiveSession = $false
	
	# Program Spec
	$progSpec = New-Object VMware.Vim.GuestProgramSpec
	# Full path to the command to run inside the guest
	$progSpec.programPath = "$guest_command_path"
	$progSpec.workingDirectory = "/tmp"
	# Arguments to the command path, must include "++goup=host/vim/tmp" as part of the arguments
	$progSpec.arguments = "++group=host/vim/tmp $guest_command_args"
	
	# Issue guest op command
	$cmd_pid = $procMgr.StartProgramInGuest($vm_moref,$auth,$progSpec)
}

#######################
## Static parameters ##
#######################
$Vcenter = "your-vcenter-address"
$DataCenter = "vc-datacenter-name"
$WitnessFolder = "location-for-witness-host"

$domainName = "domain.name"

$ClusterName = "$LocationCode-VSAN"

$ESXi1Name = "$LocationCode-esx-001"
$ESXi2Name = "$LocationCode-esx-002"
$ESXi3Name = "$LocationCode-esx-003"

$WitnessName = "$LocationCode-esx-004"
$WitnessFQDN = $WitnessName + $domainName

$WitnessVLAN = 100
$WitnessNetworkName = "$LocationCode-SRV-$WitnessVLAN"

$WitnessTargetDSName = "$ESXi3Name-R1-2"
$WitnessR5DS = "$ESXi3Name-R5-3"

$VMNetworkVLAN = 200
$VMNetworkName = "$LocationCode-VM-$VMNetworkVLAN"

#IPs for the vmk's of the two vsan hosts which will be direct linked.
$ESXi1vmk1Ip = "192.168.1.1"
$ESXi1vmk2Ip = "192.168.2.1"
$ESXi2vmk1Ip = "192.168.1.2"
$ESXi2vmk2Ip = "192.168.2.2"
$vmkMask = "255.255.255.0"

$WitnessSN = "255.255.255.0"
if(!$WitnessGW){
    $splitWitnIp = $WitnessIP.split(".")
    $WitnessGW = $splitWitnIp[0] + "." + $splitWitnIp[1] + "." + $splitWitnIp[2] + ".1" 
}

$DNSPrim = "1.1.1.1"
$DNSSec = "2.2.2.2"

$NTPServer = "3.3.3.3"
$SyslogServer = "tcp://4.4.4.4:1514"

$OVF_File = "c:\temp\VMware-vSAN-Witness-6.5.0.update01-5969303.ova"
$OVF_DeploymentOption = "tiny"

##################
## Verification ##
##################
$output = @"
#######################################################################

The script will be run with the following parameters:

    ## vCenter info ##
    VCenter: $Vcenter
    DataCenter: $DataCenter

    ## Cluster info ##
    ClusterName: $ClusterName
    Witness Folder: $WitnessFolder

    ## Physical ESX info ##
    ESX-001: $ESXi1Name
    ESX-002: $ESXi1Name
    ESX-003: $ESXi1Name
    
    ## Datastores ##
    Witness datastore (R1): $WitnessTargetDSName
    Witness datastore (R5): $WitnessR5DS

    ## OVF ##
    OVF file: $OVF_File
    Deployment option: $OVF_DeploymentOption

    ## ESXi VMK ##
    ESX-001 vmk1: $ESXi1vmk1Ip
    ESX-001 vmk2: $ESXi1vmk2Ip

    ESX-002 vmk1: $ESXi2vmk1Ip
    ESX-002 vmk2: $ESXi2vmk2Ip

    Subnet mask: $vmkMask

    ## Witness network info ##
    Witness name: $WitnessName
    Witness FQDN: $WitnessFQDN
    Witness IP: $WitnessIP
    Witness GW: $WitnessGW
    Witness Subnet mask: $WitnessSN
    Witness network name (pg): $WitnessNetworkName
    
    ## VM network ##
    VM Network Name: $VMNetworkName

    ## DNS servers ##
    Primary: $DNSPrim
    Secondary: $DNSSec

    ## NTP and Syslog server ##
    NTP: $NTPServer
    Syslog: $SyslogServer

#######################################################################
"@
Write-Output $output
$answer = Read-Host -Prompt "Do you want to continue (y/n)?"
if($answer -ne "y" -and $answer -ne "yes"){
    break
}
else{
    $output | Out-File -FilePath C:\temp\$LocationCode-VSAN-Setup-Params.txt
}

################
## User input ##
################
$start = Get-Date
$esxCredentials = Get-Credential -UserName root -Message "Please specify esxi root credentials"

########################
## Connect to vCenter ##
########################
Write-Output "Connecting to vCenter"
$session = Connect-VIServer $vcenter

##################################
## Ping hosts before continuing ##
##################################
if(!(Test-Connection -ComputerName $ESXi1Name -Count 2 -ErrorAction SilentlyContinue)){
    Write-Error "Host $ESXi1Name not responding"
    break
}
if(!(Test-Connection -ComputerName $ESXi2Name -Count 2 -ErrorAction SilentlyContinue)){
    Write-Error "Host $ESXi2Name not responding"
    break
}
if(!(Test-Connection -ComputerName $ESXi3Name -Count 2 -ErrorAction SilentlyContinue)){
    Write-Error "Host $ESXi3Name not responding"
    break
}

####################
## Create cluster ##
####################
Write-Output "Creating cluster"
if(Get-Cluster -Name $ClusterName -ErrorAction SilentlyContinue){
    Write-Warning "Cluster already exists"
    $cluster = Get-Cluster -Name $ClusterName
}
else{
    $cluster = New-Cluster -Name $ClusterName -Location $DataCenter -HAEnabled:$false -DrsEnabled:$true
}

#########################
## Add host to cluster ##
#########################
$added = $false
Write-Output "Adding hosts to vCenter"
if(!(Get-VMHost -Name $ESXi1Name*)){
    $vmhost1 = Add-VMHost -Name $ESXi1Name -Location $cluster -Credential $esxCredentials -Force
    $added = $true
}
else{
    $vmhost1 = Get-VMHost -Name $ESXi1Name*
}
if(!(Get-VMHost -Name $ESXi2Name*)){
    $vmhost2 = Add-VMHost -Name $ESXi2Name -Location $cluster -Credential $esxCredentials -Force
    $added = $true
}
else{
    $vmhost2 = Get-VMHost -Name $ESXi2Name*
}
if(!(Get-VMHost -Name $ESXi3Name*)){
    $vmhost3 = Add-VMHost -Name $ESXi3Name -Location $WitnessFolder -Credential $esxCredentials -Force
    $added = $true
}
else{
    $vmhost3 = Get-VMHost -Name $ESXi3Name*
}

$vmhosts = Get-VMHost $vmhost1,$vmhost2,$vmhost3

##########################
## Sleep for 30 seconds ##
##########################
if($added){
    Write-Output "Sleeping for 30 seconds..."
    Start-Sleep -seconds 30
}

########################################################
## Set hosts in maintenance and disable alarm actions ##
########################################################
Write-Output "Setting hosts in maintenance mode and disable alarm actions"
$alarmMgr = Get-View AlarmManager
$vmhost1 | Set-VMHost -State Maintenance -Confirm:$false | Out-Null
$alarmMgr.EnableAlarmActions($vmhost1.ExtensionData.MoRef,$false)
$vmhost2 | Set-VMHost -State Maintenance -Confirm:$false | Out-Null
$alarmMgr.EnableAlarmActions($vmhost2.ExtensionData.MoRef,$false)
$alarmMgr.EnableAlarmActions($vmhost3.ExtensionData.MoRef,$false)

#########################
## Host Network config ##
#########################
Write-Output "Configure host networking"
foreach($vmhost in $vmhosts){
    Write-Output "Configuring host $($vmhost.name)"
    
	$hostAdapters = Get-VMHostNetworkAdapter -VMHost $vmhost -Physical
	$hostSwitches = Get-VirtualSwitch -VMHost $vmhost -Standard
	$vsw0 = $hostSwitches | where {$_.name -eq "vswitch0"}

	$vmnic1 = $hostAdapters | where {$_.name -eq "vmnic1"}

    Write-Output "Add vmnic1 to vSwitch0"
	Add-VirtualSwitchPhysicalNetworkAdapter -VMHostPhysicalNic $vmnic1 -VirtualSwitch $vsw0 -Confirm:$false

    Write-Output "Change NIC teaming policy on vSwitch0 to active/standby"
    $pol0 = Get-NicTeamingPolicy -VirtualSwitch $vsw0
    Set-NicTeamingPolicy -VirtualSwitchPolicy $pol0 -MakeNicActive vmnic0 -MakeNicStandby vmnic1

    if($vmhost -eq $vmhost3){
        Write-Verbose "No more IP config for this host"
        continue
    }
    elseif($vmhost -eq $vmhost1){
        $vmk1Ip = $ESXi1vmk1Ip
        $vmk2Ip = $ESXi1vmk2Ip
    }
    elseif($vmhost -eq $vmhost2){
        $vmk1Ip = $ESXi2vmk1Ip
        $vmk2Ip = $ESXi2vmk2Ip
    }
    else{
        Write-Error "Couldn't set vmkernel adapter IP"
        continue
    }

    Write-Output "Create switch and portgroup for VM traffic"	
    $vsw1 = New-VirtualSwitch -VMHost $vmhost -Name vSwitch1 -Nic vmnic2,vmnic3
    Write-Output "Change NIC teaming policy on vSwitch1 to active/standby"
    $pol1 = Get-NicTeamingPolicy -VirtualSwitch $vsw1
    Set-NicTeamingPolicy -VirtualSwitchPolicy $pol1 -MakeNicActive vmnic0 -MakeNicStandby vmnic1

	$vmPG = New-VirtualPortGroup -VirtualSwitch $vsw1 -VLanId 20 -Name $VMNetworkName | Out-Null

    Write-Output "Create switches and portgroups for VMotion and VSAN traffic"	
	$vsw2 = New-VirtualSwitch -VMHost $vmhost -Name vSwitch2 -Nic vmnic4 | Out-Null
	$vmPG1 = New-VirtualPortGroup -VirtualSwitch $vsw2 -Name "VSAN-vMotion-1" | Out-Null
	$vmk1 = New-VMHostNetworkAdapter -VMHost $vmhost -PortGroup $vmPG1 -VirtualSwitch $vsw2 -IP $vmk1Ip -SubnetMask $vmkMask -VMotionEnabled:$true -VsanTrafficEnabled:$true | Out-Null

	$vsw3 = New-VirtualSwitch -VMHost $vmhost -Name vSwitch3 -Nic vmnic5
	$vmPG2 = New-VirtualPortGroup -VirtualSwitch $vsw3 -Name "VSAN-vMotion-2" | Out-Null
	$vmk2 = New-VMHostNetworkAdapter -VMHost $vmhost -PortGroup $vmPG2 -VirtualSwitch $vsw3 -IP $vmk2Ip -SubnetMask $vmkMask -VMotionEnabled:$true -VsanTrafficEnabled:$true | Out-Null
}

#######################################
## Create mgmt portgroup for witness ##
#######################################
Write-Output "Creating management pg on Witness target host"
$witnessTargetHost = Get-VMHost $ESXi3Name*
$witvsw0 = Get-VirtualSwitch -VMHost $WitnessTargetHost -Name vSwitch0
$createWitmgmtPg = New-VirtualPortGroup -VirtualSwitch $witvsw0 -Name $WitnessNetworkName -VLanId $WitnessVLAN
$witmgmtPg = Get-VirtualPortGroup -VMHost $witnesstargethost -VirtualSwitch vswitch0 -Name $WitnessNetworkName

##################################
## Create datastore for witness ##
##################################
Write-Output "Creating datastores on Witness target host"

$hbas = Get-VMHostHba -VMHost $witnesstargethost
$r1DiskLun = $hbas | where {$_.Type -eq "ParallelScsi"} | Get-ScsiLun
$r5DiskLun = $hbas | where {$_.Type -eq "Block"} | Get-ScsiLun -CanonicalName naa*

$r1DiskPath = $r1DiskLun.CanonicalName
New-Datastore -VMHost $witnessTargetHost -Name $WitnessTargetDSName -Vmfs -FileSystemVersion 6 -Path $r1DiskPath | Out-Null

$r5DiskPath = $r5DiskLun.CanonicalName
New-Datastore -VMHost $witnessTargetHost -Name $WitnessR5DS -Vmfs -FileSystemVersion 6 -Path $r5DiskPath | Out-Null

##Scan for new datastore
$witnessTargetDS = $witnessTargetHost | Get-Datastore $WitnessTargetDSName

####################
## Deploy witness ##
####################
Write-Output "Deploying virtual Witness host - This will take some time...."

$pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($esxCredentials.Password))
$ovfConfig = Get-OvfConfiguration -Ovf $OVF_File
$ovfConfig.DeploymentOption.Value = $OVF_DeploymentOption
$ovfConfig.NetworkMapping.Witness_Network.Value = "VM Network"
$ovfConfig.NetworkMapping.Management_Network.Value = "VM Network"
$ovfConfig.vsan.witness.root.passwd.Value = $pass

Import-VApp -Source $OVF_File -OvfConfiguration $ovfConfig -Name $WitnessName -Location $witnessTargetHost -VMHost $witnessTargetHost -Datastore $witnessTargetDS -DiskStorageFormat EagerZeroedThick | Out-Null

$witnessVM = Get-VM $WitnessName
$witnessVM | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $witmgmtPg -StartConnected $true -Confirm:$false -ErrorAction Stop -ErrorVariable netErr | Out-Null
if($netErr){
    Write-Error "Couldn't change network adapter on witness appliance"
}

$witnessVM | Start-VM | Out-Null
Write-Output "Waiting for VM Tools to Start"
do {
	$toolsStatus = (Get-VM $WitnessName | Get-View).Guest.ToolsStatus
	Write-Output $toolsStatus
	sleep 5
} until ( $toolsStatus -eq 'toolsOk' )

Write-Output "Configuring virtual Witness host"
$Command_Path = '/bin/python'
$CMD_MGMT = '/bin/esxcli.py network ip interface ipv4 set -i vmk0 -I ' + $WitnessIP + ' -N ' + $WitnessSN  + ' -t static;/bin/esxcli.py network ip route ipv4 add -N defaultTcpipStack -n default -g ' + $WitnessGW + ';/bin/esxcli.py network vswitch standard portgroup set -p "Management Network"'
$CMD_DNS = '/bin/esxcli.py network ip dns server add --server=' + $DNSPrim + ';/bin/esxcli.py network ip dns server add --server=' + $DNSSec + ';/bin/esxcli.py system hostname set --fqdn=' + $WitnessFQDN

runGuestOpInESXiVM -vm_moref $witnessVM.ExtensionData.MoRef -guest_command_path $command_path -guest_command_args $CMD_MGMT -guest_password $pass
runGuestOpInESXiVM -vm_moref $witnessVM.ExtensionData.MoRef -guest_command_path $command_path -guest_command_args $CMD_DNS -guest_password $pass

######################
## Add witness host ##
######################
Write-Output "Adding virtual Witness host to vCenter"

if(!(Test-Connection -ComputerName $WitnessName -Count 3 -ErrorAction SilentlyContinue)){
    Write-Error "Host $WitnessName not responding"
    break
}

$witnessHost = Add-VMHost -Name $WitnessFQDN -Location $WitnessFolder -Credential $esxCredentials -Force | Out-Null

Write-Output "Sleeping for 20 seconds"
Start-Sleep -Seconds 20

###################################
## Network settings witness host ##
###################################
#Enable VSAN on vmk0 and remove witnessSwitch
Write-Output "Configuring network on virtual Witness host"

$witnessVSW0 = Get-VirtualSwitch -VMHost $witnessHost -Standard -Name vSwitch0
$witnessVMK0 = Get-VMHostNetworkAdapter -VMHost $witnessHost -VirtualSwitch $witnessVSW0 -VMKernel -Name vmk0
Set-VMHostNetworkAdapter -VirtualNic $witnessVMK0 -VsanTrafficEnabled:$true -Confirm:$false | Out-Null
$witnessVMK1 = Get-VMHostNetworkAdapter -VMHost $witnessHost -VMKernel -Name vmk1
Remove-VMHostNetworkAdapter -Nic $witnessVMK1 -Confirm:$false | Out-Null
$witnessSwitch = Get-VirtualSwitch -VMHost $witnessHost -Standard -Name witnessSwitch
$witnessSwitch | Remove-VirtualSwitch -Confirm:$false | Out-Null

########################################
## Standard ESXi config for all hosts ##
########################################
$vmhosts += $witnessHost

Write-Output "Setting standard config for ESXi"
foreach($vmhost in $vmhosts){
    Write-Output "Configuring host $($vmhost.name)"

    $settings = $vmhost | Get-AdvancedSetting
    
    # Remove ssh warning..
    Write-Output "Configuring ssh warning"
    $settings | where {$_.name -eq "UserVars.SuppressShellWarning"} | Set-AdvancedSetting -Value '1' -Confirm:$false | Out-Null
    
    Write-Output "Configuring syslog"
    $vmhost | Set-VMHostSysLogServer -SyslogServer $syslogserver | Out-Null
    $vmhost | Get-VMHostService | where {$_.Key -eq "vmsyslogd"} | Restart-VMHostService -Confirm:$false | Out-Null
    $vmhost | Get-VMHostFirewallException | where {$_.Name -eq "syslog"} | Set-VMHostFirewallException -Enabled $true | Out-Null

    Write-Output "Configuring ssh"
    $vmhost | Get-VMHostService | where {$_.Key -eq "TSM-SSH"} | Set-VMHostService -Policy "On" | Out-Null
    $vmhost | Get-VMHostFirewallException | where {$_.Name -eq "SSH Server"} | Set-VMHostFirewallException -Enabled $true | Out-Null
    $vmhost | Get-VMHostService | where {$_.Key -eq "TSM-SSH"} | Start-VMHostService -Confirm:$false | Out-Null

    Write-Output "Configuring ntp"
    $vmhost | Get-VMHostService | where {$_.Key -eq "ntpd"} | Set-VMHostService -Policy "On" | Out-Null
    if(($vmhost | Get-VMHostNtpServer) -ne $NTPServer){
        $vmhost | Add-VMHostNtpServer -NtpServer $ntpServer | Out-Null
        $vmhost | Get-VMHostFirewallException | where {$_.Name -eq "NTP Client"} | Set-VMHostFirewallException -Enabled $true | Out-Null
        $vmhost | Get-VMHostService | where {$_.Key -eq "ntpd"} | Restart-VMHostService -Confirm:$false | Out-Null
    }

    Write-Output "Configuring power settings"
    (Get-View ($vmhost | Get-View).ConfigManager.PowerSystem).ConfigurePowerPolicy(1)

    Write-Output "Configuring DNS"
    $vmhost | Get-VMHostNetwork | Set-VMHostNetwork -DomainName $domainName -DNSAddress $DNSPrim , $DNSSec -Confirm:$false | Out-Null
}

#################
## Enable VSAN ##
#################
Write-Output "Enabling VSAN on cluster"
$cluster | Set-Cluster -VsanEnabled:$true -Confirm:$false

################
## Diskgroups ##
################
Write-Output "Creating VSAN disk groups"

$vsanhosts = $vmhost1,$vmhost2
foreach($vsanhost in $vsanhosts){
    Write-Output "Exiting maintenance mode for host $($vsanhost.name)"
    $vsanhost | Set-VMHost -State Connected | Out-Null
    while((Get-VMHost $vsanhost).State -ne "Connected"){
        Start-Sleep -seconds 5
    }

    Write-Output "Creating disk groups for host $($vsanhost.name)"
    $hba = Get-VMHostHba -VMHost $vsanhost -Device vmhba1
    $luns = $hba | Where-Object {$_.Type -eq "Block"} | Get-ScsiLun -CanonicalName naa*

    $ssdDisks = $luns | Where-Object {$_.IsSsd}
    $capDisks = $luns | Where-Object {!$_.IsSsd}

    $capDiskArray1 = @()
    $capDiskArray2 = @()
    $capDiskArray1 += $capDisks[0].CanonicalName
    $capDiskArray1 += $capDisks[1].CanonicalName
    $capDiskArray2 += $capDisks[2].CanonicalName
    $capDiskArray2 += $capDisks[3].CanonicalName

    New-VsanDiskGroup -VMHost $vsanhost -SsdCanonicalName $ssdDisks[0].CanonicalName -DataDiskCanonicalName $capDiskArray1 | Out-Null
    New-VsanDiskGroup -VMHost $vsanhost -SsdCanonicalName $ssdDisks[1].CanonicalName -DataDiskCanonicalName $capDiskArray2 | Out-Null
}

$witnessHba = Get-VMHostHba -VMHost $witnessHost -Device vmhba1
$witnessLuns = $witnessHba | Get-ScsiLun
$ssdLun = $witnessLuns | Where-Object {$_.CanonicalName -eq "mpx.vmhba1:c0:t2:l0"}
$capLun = $witnessLuns | Where-Object {$_.CanonicalName -eq "mpx.vmhba1:c0:t1:l0"}

Write-Output "Sleeping for 20 seconds"
Start-Sleep -Seconds 20

###############################
## Configure witness traffic ##
###############################
Write-Output "Configure witness traffic on management vmk"
foreach($vsanhost in $vsanhosts){
    $esxcli = Get-EsxCli -VMHost $vsanhost -V2
    $esxcli.vsan.network.ip.add.Invoke(@{interfacename="vmk0";traffictype="witness"})
}

Write-Output "Sleeping for 20 seconds"
Start-Sleep -Seconds 20
#########################
## Reconfigure cluster ##
#########################
Write-Output "Configuring VSAN Fault domains"

$primaryFd = New-VsanFaultDomain -Name 'Preferred' -VMHost $vmhost1 | Out-Null
$secondaryFd = New-VsanFaultDomain -Name 'Secondary' -VMHost $vmhost2 | Out-Null

Write-Output "Reconfiguring VSAN cluster to include witness host and fault domains"
Set-VsanClusterConfiguration -Configuration $cluster -StretchedClusterEnabled $true -PreferredFaultDomain $primaryFd -WitnessHost $witnessHost -WitnessHostCacheDisk $ssdLun.CanonicalName -WitnessHostCapacityDisk $capLun.CanonicalName -PerformanceServiceEnabled:$true -Confirm:$false | Out-Null

$stop = Get-Date
$timespan = New-TimeSpan -Start $start -End $stop
$mins = [math]::Round($timespan.TotalMinutes,2)

Write-Output "#####################################"
Write-Output "## Script finished in $mins minutes ##"
Write-Output "#####################################"