<#
# Description: Sets tentacle service user permissions needed to deploy IIS websites
#              without administration rights on the Windows Server
#
# @Version: 1.0.0
#>

param (
    [string] $svcAccountName="tentaclesvc",
    [string] $svcAccountDomain,
    [string] $octoInstallDir="C:\OctopusDeploy\Tentacle\Files",
    [string] $octoInstanceDir="C:\OctopusDeploy\Tentacle\Instance"
)

$iisFolder = "c:\windows\system32\inetsrv"

# Ahadmin DCOM registry key (IIS)
$ahadmin_reg = "SOFTWARE\Classes\AppID\{9fa5c497-f46d-447f-8011-05d03d7d7ddc}"
$ahadminAppID = "{9fa5c497-f46d-447f-8011-05d03d7d7ddc}"

# Output formatting
$fgcSuccess = "DarkGreen"
$fgcInfo = "White"

<#
# Functions
#>
#region Registry Functions
# Privileges need to be adjusted before being able to take ownership of registry
function Adjust-Privilege ([int] $privilege, [bool] $enable)
{
    $adjustPrivilege = @"
    using System;
    using System.Runtime.InteropServices;

    namespace Win32Api {
        public class NtDll {
        [DllImport("ntdll.dll", EntryPoint="RtlAdjustPrivilege")]
        public static extern int RtlAdjustPrivilege(ulong Privilege, bool Enable, bool CurrentThread, ref bool Enabled);
        }
    }
"@
    if (! ([System.Management.Automation.PSTypeName]'Win32Api.NtDll').Type)
    {
        Add-Type -TypeDefinition $adjustPrivilege -PassThru | Out-Null
    }

    $enabledBool = $enable
    $res = [Win32Api.NtDll]::RtlAdjustPrivilege($privilege, $true, $false, [ref]$enabledBool)
}

function Take-RegOwnership ([string] $key, [string] $secAccount)
{
    Write-Host "Checking current owner for 'HKLM:\$key'..." -ForegroundColor $fgcInfo
    $keyObj = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($key, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
    $acl = $keyObj.GetAccessControl()

    try {
        Write-Host "Adjusting privileges..." -ForegroundColor $fgcInfo
        Adjust-Privilege 9 $true

        Write-Host "Setting $secAccount as owner..." -ForegroundColor $fgcInfo
        $filterError = $acl.SetOwner([System.Security.Principal.NTAccount] $secAccount)

        $keyObj.SetAccessControl($acl)
        Write-Host "Owner set successfuly" -ForegroundColor $fgcSuccess
    }
    catch {
        Write-Host $_.Exception.Message -ForeGroundColor Red
    }
}

function Set-RegPermissions ([string] $key, [string] $secAccount)
{
    # The reg root is hard-coded from a .NET library. It's currently set to LocalMachine
    $keyObj = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($key, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::ChangePermissions)
    $acl = $keyObj.GetAccessControl()

    $access = [System.Security.AccessControl.RegistryRights] "FullControl"
    $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $propagation = [System.Security.AccessControl.PropagationFlags] "None"
    $type = [System.Security.AccessControl.AccessControlType] "Allow"
    $rule = New-Object System.Security.AccessControl.RegistryAccessRule ($secAccount, $access, $inherit, $propagation, $type)

    Write-Host "Setting registry permissions for $secAccount on $key..." -ForegroundColor $fgcInfo
    try {
        $acl.SetAccessRule($rule)
        $keyObj.SetAccessControl($acl)

        Write-Host "Registry permissions set successfully" -ForegroundColor $fgcSuccess
    }
    catch {
        Write-Host $_.Exception.Message -ForeGroundColor Red
    }
}
#endregion

#region DCOM function
function setAppDCOMLaunchPermissions ([string] $appID, [string] $accountDomain, [string] $accountName) {
    $wmiApp = Get-WMIObject -Class Win32_DCOMApplicationSetting -Filter "AppID='$appID'" -EnableAllPrivileges

    $sdRes = $wmiApp.GetLaunchSecurityDescriptor()
    $sd = $sdRes.Descriptor

    $trustee = ([wmiclass] 'Win32_Trustee').CreateInstance()
    $trustee.Domain = $accountDomain
    $trustee.Name = $accountName

    $localLaunchActivate = 11
    $ace = ([wmiclass] 'Win32_ACE').CreateInstance()
    $ace.AccessMask = $localLaunchActivate
    $ace.AceFlags = 0
    $ace.AceType = 0
    $ace.Trustee = $trustee
    [System.Management.ManagementBaseObject[]] $newDACL = $sd.DACL + @($ace)
    $sd.DACL = $newDACL

    Write-Host "Setting the LaunchSecurityDescriptor..." -ForegroundColor $fgcInfo
    try {
        $wmiApp.SetLaunchSecurityDescriptor($sd) | Out-Null

        Write-Host "LaunchSecurityDescriptor was set successfully for $accountDomain\$accountName" -ForegroundColor $fgcSuccess
    }
    catch {
        Write-Host $_.Exception.Message -ForeGroundColor Red
    }
}
#endregion

<#
# Main
#>
Clear-Host

Write-Host "Setting FullControl permissions for $svcAccountName on $octoInstallDir" -ForegroundColor $fgcInfo
& icacls $octoInstallDir /grant:r $svcAccountName":(OI)(CI)(F)" /T
Write-Host "Setting FullControl permissions for $svcAccountName on $octoInstanceDir" -ForegroundColor $fgcInfo
& icacls $octoInstanceDir /grant:r $svcAccountName":(OI)(CI)(F)" /T

Write-Host "Setting permissions for $svcAccountName on the IIS folder $iisFolder" -ForegroundColor $fgcInfo
& takeown /F $iisFolder /A
& icacls $iisFolder /grant:r $svcAccountName":(OI)(CI)(F)"

Write-Host "Setting IIS registry permissions for $svcAccountName" -ForegroundColor $fgcInfo

$secAccount = "$svcAccountDomain\$svcAccountName"

Take-RegOwnership $ahadmin_reg $secAccount
Set-RegPermissions $ahadmin_reg $secAccount

Write-Host "Setting IIS DCOM Launch Permissions for $svcAccountName..." -ForegroundColor $fgcInfo
setAppDCOMLaunchPermissions $ahadminAppID $svcAccountDomain $svcAccountName

Write-Host ""
Write-Host "All done" -ForegroundColor $fgcSuccess
