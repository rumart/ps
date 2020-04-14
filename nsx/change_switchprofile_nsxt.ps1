<#
    .SYNOPSIS
        A script for changing a profile on a NSX-T logical switch
    .DESCRIPTION
        The script will change the Switch profile of the given type
        on a NSX-T logical switch

        Note that the script will only work with switches that have the
        protection level set to NOT_PROTECTED

        The script is only tested against NSX-T 2.4.
    .LINK
        https://rudimartinsen.com/2020/04/13/change-nsx-t-switch-profiles-with-powercli
    .NOTES
        Author: Rudi Martinsen / Proact IT Norge AS
        Created: 12/4-2020
        Version: 0.1.0
        Changelog:
    .PARAMETER Network
        Name of the logical network / switch
    .PARAMETER ProfileType
        The type of switch profile
    .PARAMETER ProfileName
        The name of the new profile
    .PARAMETER NSXManager
        The NSX Manager to connecto to
    .PARAMETER Credential
        A credential object for authenticating with NSX manager
#>
##############
# Parameters #
##############
param(
    $LogicalNetwork,
    [ValidateSet("SwitchSecuritySwitchingProfile","SpoofGuardSwitchingProfile","IpDiscoverySwitchingProfile","MacManagementSwitchingProfile","PortMirroringSwitchingProfile","QosSwitchingProfile")]
    $ProfileType,
    $ProfileName,
    $NSXManager,
    [PSCredential]
    $Credential
)
#Skip SSL validation
add-type @" 
    using System.Net; 
    using System.Security.Cryptography.X509Certificates; 
    public class TrustAllCertsPolicy : ICertificatePolicy { 
        public bool CheckValidationResult( 
            ServicePoint srvPoint, X509Certificate certificate, 
            WebRequest request, int certificateProblem) { 
            return true; 
        } 
    } 
"@  
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
$AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

#Connect to NSX mgr
Connect-NsxtServer -Server $NSXManager -Credential $Credential

#Get the new profile
$nestProfile = (Get-NsxtService -Name "com.vmware.nsx.switching_profiles").list().results.Where({$_.resource_type -eq $ProfileType -and $_.display_name -eq $ProfileName})

if(!$nestProfile){
    throw "No profile found!"
}

#Get the logical switch
$sw = (Get-NsxtService "com.vmware.nsx.logical_switches").list().results.Where({$_.display_name -eq $LogicalNetwork})[0]
if(!$sw){
    throw "No logical switch found!"
}

#Get the current profiles and get index of profile type
$swProfiles = $sw.switching_profile_ids
$profIndex = 0;
for($i=0;$i -le $swProfiles.count;$i++){
    if($swProfiles[$i].key -eq $ProfileType){
        $profIndex = $i
        break
    }
}

#Set new value
$chgProfile = $swProfiles[$profIndex]
$chgProfile.value = $nestProfile.id

#Change existing switch
$swProfiles[$profIndex] = $chgProfile
$sw.switching_profile_ids = $swProfiles

#Update switch
(Get-NsxtService -Name "com.vmware.nsx.logical_switches").update($sw.id,$sw)
