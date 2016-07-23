<#
# Description: Initializes and finalizes web components
#
# @Version: 1.0.10
#>

# Used when in consoleMode
try {
    Import-Module .\lib\common.psm1 -DisableNameChecking -Force
    Import-Module .\lib\iis.psm1 -DisableNameChecking -Force
    Import-Module .\lib\io.psm1 -DisableNameChecking -Force
    Import-Module .\lib\octopus.psm1 -DisableNameChecking -Force
}
catch {}

#region Configuration
<#
# Settings
#>
$ErrorActionPreference = "Stop"

$WarningPreference = "Continue"
$VerbosePreference = "Continue"
## Debuging feature is not completed yet. Last edit was on the completion of newDeployment function
#$DebugPreference = "Continue"

# Sets the required powershell version to run this script
$required_PSVersion = 4

# Sets consoleMode
$global:console_Mode = $false

$fcDEPLOYSTART = "DarkBlue"
$fcDEPLOYOPTIONSHEADER = "DarkCyan"
$fcDEPLOYOPTIONSEXT = "DarkCyan"
$fcDEPLOYHIGHLIGHT = "DarkBlue"
$fcDEPLOYSUCCESS = "DarkGreen"
$fcDEPLOYINFO = "DarkGray"

$DATEFORMAT = "HH:mm:ss dd/MM/yyyy ('GMT'z)"
#endregion

<#
# Initialises the deployment
# Anything that has to be done before the deployment should be done here
#>
function initDeploy {
    Clear-Host
    Write-Debug "[initDeploy] Deployment Started"
    Write-Debug "[initDeploy] Printing args"
    $Args | Format-List | Write-Debug

    checkPSVersion
    isRunningConsole
    newDeployment @Args
    initWeb
}

<#
# Creates a configuration object for deployment
# Supports two modes: 'Website' or 'WebApp'
#
## Using default parameterset
## Reason for not using other builtin parameter validation: When using this functionality, powershell stops on the first error.
## Grouping all errors and show them at once is more benefical, so no time is wasted in the deployment
#>
function newDeployment {
    param(
        # Website parameters
        [string] $WebsiteName,
        [string] $WebsitePhysicalPath,
        [string] $WebsitePoolName,
        [string] $WebsiteProtocol="http",
        [string] $WebsiteIPBinding="*",
        [int] $WebsitePort=80,
        [string] $WebsiteHost,
        [string] $WebsitePoolType,
        [string] $WebsitePoolUsername,
        [string] $WebsitePoolPassword,
        [string] $WebsitePoolNetVersion,

        # Application parameters
        [string] $ApplicationName,
        [string] $ApplicationPhysicalPath,
        [string] $ApplicationPoolName,
        [string] $ApplicationPoolType,
        [string] $ApplicationPoolUsername,
        [string] $ApplicationPoolPassword,
        [string] $ApplicationPoolNetVersion,
    
        # Configuration
        [string] $Mode=$null,
        [string] $PackagePath,
        [int] $HealthSwitch=0,
        [string] $HealthPath,
        [int] $HealthDelay
    )

    Write-Debug "[newDeployment] Entered"

    $all_params = @{}
    $all_params = @{
        websiteName = $WebsiteName
        websitePhysicalPath = $WebsitePhysicalPath
        websitePoolName = $WebsitePoolName
        websiteProtocol = $WebsiteProtocol
        websiteIPBinding = $WebsiteIPBinding
        websitePort = $WebsitePort
        websiteHost = $WebsiteHost
        websitePoolType = $WebsitePoolType
        websitePoolUsername = $WebsitePoolUsername
        websitePoolPassword = $WebsitePoolPassword
        websitePoolNetVersion = $WebsitePoolNetVersion

        applicationName = $ApplicationName
        applicationPhysicalPath = $ApplicationPhysicalPath
        applicationPoolName = $ApplicationPoolName
        applicationPoolType = $ApplicationPoolType
        applicationPoolUsername = $ApplicationPoolUsername
        applicationPoolPassword = $ApplicationPoolPassword
        applicationPoolNetVersion = $ApplicationPoolNetVersion

        mode = $Mode
        packagePath = $PackagePath
        healthSwitch = $(convertHealthSwitch $HealthSwitch)
        HealthPath = $HealthPath
        healthDelay = $HealthDelay
    }

    $deployStartTime = (Get-Date)
    setVar -Name "deployStartTime" -Value $deployStartTime
    $startTime = $deployStartTime.ToString($DATEFORMAT)

    Write-Host "Starting deployment at $startTime" -ForeGroundColor $fcDEPLOYSTART
    Write-Host " "

    $verified_params = validateParams -UsedParams $PSBoundParameters -AllParams $all_params

    # After validation has passed creates custom object and assigns a name to it
    # Octopus: It will only be used on initWebApp method. After that it goes out of scope
    # Console: It uses the same object across the deployment
    $script:obj_deploy = $null
    $script:obj_deploy = New-Object PSCustomObject -Property $verified_params
    $script:obj_deploy.PSObject.TypeNames.Insert(0,'DeploymentConfiguration')

    Write-Debug "[newDeployment] Object created"

    if (! $global:console_Mode) {
        Write-Debug "Console mode is false. Calling convert of object variables to Octopus"
        convertVarsOcto $verified_params
    }
}

# Custom validation of the parameters
function validateParams {
    param (
        $UsedParams,
        [hashtable] $AllParams
    )

    $script:param_error = ""

    # Checks for empty values on the mandatoy parameters
    function checkMandatory {
        param (
            [array] $MParams
        )

        # Concatenation of mandatory parameters for display purposes
        $mod_params = ""
        for ($i=0; $i -lt $MParams.Count -1; $i++) {
            $mod_params += $MParams[$i] + ", "
        }
        $mod_params += $MParams[-1]

        Write-Host "Checking mandatory parameters: $mod_params"
        Write-Host " "

        $has_all_mandatory = $true
        foreach ($_param in $MParams) {
            if (! $UsedParams.ContainsKey($_param)) {
                Write-Warning "$_param cannot be empty"
                
                $has_all_mandatory = $false
            }
        }
        if (! $has_all_mandatory) {
            exit 1
        }
    }

    function checkMode {
        if (($AllParams["mode"] -ine "Website") -and ($AllParams["mode"] -ine "WebApp")) {
            $script:param_error += "Please specify -Mode [Website|WebApp]"
        }
    }

    function checkBinding {
        Write-Debug "Verifying the binding"

        # Validates website protocol
        if (($AllParams["websiteProtocol"] -ne "http") -and ($AllParams["websiteProtocol"] -ne "https")) {
            $script:param_error += "Website protocol must be `'http`' or `'https`'`n"
        }

        # Validates website port
        try {
            Write-Debug "Trying to convert websitePort to validate the port"

            [int] $website_port_int = $AllParams["websitePort"]

            if (! (($website_port_int -gt 0) -and ($website_port_int -le 65535))) {
                $script:param_error += "Website port is invalid. Must be a number between 1-65535`n"
            }
        }
        catch {
            $script:param_error += "Website port is invalid. Must be a number between 1-65535`n"
        }
    }

    # Application pool name cannot be longer than 64 characters
    function checkAppPool {
        param (
            [array] $PoolName
        )
        
        Write-Debug "Validating Application Pool length"

        for ($i=0; $i -lt $PoolName.Length; $i++) {
            if (! (($PoolName[$i].Length -gt 0) -and ($PoolName[$i].Length -le 64))) {
                $script:param_error += "ApplicationPool $($PoolName[$i]) is invalid. Value must be between 1-64 characters`n"
            }

            if (($PoolName[$i] -match "[!-,:-@{-~[-^/``]")) {
                $script:param_error += "ApplicationPool $($PoolName[$i]) is invalid. Only these symbols are allowed '-_.'`n"
            }
        }
    }

    <#
    # Handles basic validation as the NET Framework Version has specific syntax.
    # If managed version is not specified, uses the default one from server
    #
    ## Reason for the hashtable is the validation returns the correspondent values
    ## and so it makes sure the right values are being modified and returned
    #>
    function validatePoolNetVersion {
        param (
            [hashtable] $NetVersion
        )

        Write-Debug "Validating Application Pool NetVersion"

        $result_NetVersion = $NetVersion.Clone()
        
        ForEach ($_netversion in $NetVersion.GetEnumerator()) {
            if (! ($_netversion.Value -match "(^$)|(^\s)|(\s$)")) {
                if (! $($_netversion.Value.ToString().StartsWith("v")) -or `
                (! ($_netversion.Value -match ("v")))) {
                    $_netversion.Value = $_netversion.Value.ToString().Replace("v", "").Trim()
                    $_netversion.Value = "v" + $_netversion.Value
                }
                if (! ($_netversion.Value -match '\.')) {
                    $_netversion.Value = $_netversion.Value + ".0"
                }

                $result_NetVersion[$_netversion.Key] = $_netversion.Value
            }
        }

        return [hashtable] $result_NetVersion
    }

    function validateHealthDelay {
        param (
            [int] $HealthDelay
        )

        Write-Debug "Validating Health Delay"

        if (! ($HealthDelay -match "\d")) {
            $script:param_error += "Health delay must be a number`n"
        }
    }

    # Reports default parameters
    function reportDefaults {
        Write-Debug "Reporting default parameters used"

        if (! $UsedParams["websiteProtocol"]) {
            Write-Verbose "Website protocol not specified. Using default 'HTTP'"
        }
        if (! $UsedParams["websiteIPBinding"]) {
            Write-Verbose "Website binding not specified. Using default '*'"
        }
        if (! $UsedParams["websitePort"]) {
            Write-Verbose "Website port not specified. Using default '80'"
        }
    }

    ############
    ### MAIN ###
    ############
    Write-Debug "Start of parameter validation"
    Write-Host "=== Parameters ==="
    
    # Website
    # Mandatory parameters. Add or remove mandatory parameters to be checked
    $m_params = @("WebsiteName", "WebsitePhysicalPath", "WebsitePoolName", "WebsiteHost", "PackagePath")
    # Creates array of application pool names
    $param_pools = @($AllParams["websitePoolName"])
    # Creates hashtable of application pool .net version
    $param_netVersions = @{
        websitePoolNetVersion = $AllParams["websitePoolNetVersion"]
    }
    
    # WebApp
    ## Adds extra validations for WebApp
    if ($AllParams["mode"] -ieq "WebApp") {
        $m_params += @("ApplicationName", "ApplicationPhysicalPath", "ApplicationPoolName")
        $param_pools += $AllParams["applicationPoolName"]
        
        $param_netVersions += @{
            applicationPoolNetVersion = $AllParams["applicationPoolNetVersion"]
        }
    }

    # HealthSwitch
    if ($AllParams["healthSwitch"]) {
        $m_params += @("HealthPath")
        validateHealthDelay $AllParams["healthDelay"]
    }

    checkMode
    checkMandatory $m_params
    checkBinding
    checkAppPool $param_pools
    $new_netVersions = validatePoolNetVersion $param_netVersions
    $AllParams = mergeHashTables $AllParams $new_netVersions

    # Exits if there is an error
    if ($script:param_error -ne "") {
        throw $script:param_error
    }
    else {
        reportDefaults

        Write-Host "All parameters confirmed to be OK!"
        Write-Host " "
    }
    
    $script:param_error = $null
    return [hashtable] $AllParams
}

<#
# Checks for specific variables to see if script is running from Octopus Deploy or console
## The variable "$Host.Name", would not give the expected results
#>
function isRunningConsole {
    # Other possible vars to use to check if running from Octopus
    #Get-Variable OctopusDeploymentName
    #Get-Variable PSScriptRoot (check if running from C:\Windows\system32\config\systemprofile\AppData\Local\Tentacle\Temp)
    Write-Debug "Verifying if the script is running from Console"

    if ($(Get-Variable | Where { $_.Name -match "OctopusDeploymentId"})`
        -and $(Get-Variable | Where { $_.Name -match "OctopusReleaseNumber"})`
        -or $(Get-Variable | Where { $_.Name -match "OctopusTentacleAgentInstanceName"})) {
            
        $global:console_Mode = $false
        Write-Debug "Running mode set to Octopus"
    }
    else {
        $global:console_Mode = $true
        Write-Debug "Running mode set to Console"
    }
}

# Checks if the shell is running the required powershell version to run this script
function checkPSVersion {
    Write-Debug "Checking if Powershell Version is v$required_PSVersion..."
    Write-Debug "Printing PSVersionTable..."
    $PSVersionTable.PSVersion | Write-Debug
    
    if (Get-Variable PSVersionTable) {
        if (! (($PSVersionTable.Psversion).Major -ge $required_PSVersion)) {
            throw "Powershell v$required_PSVersion is required. Please install it and try again."
        }
    }
    else {
        throw "PowerShell v1 is not supported. Please install v$required_PSVersion and try again."
    }
    
    Write-Debug "Required Powershell version matches`n"
}

<#
# Pre-Requisites validation
# Validates existence of healthcheck and web.config transform files
#>
function checkRequisites {
    param (
        [string] $Package,
        [string] $HealthPath
    )

    Write-Host "=== PreRequisites ==="

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }
    catch {
        throw "Error importing assembly System.IO.Compression.FileSystem"
    }

    $varIO = $null
    try {
        Write-Debug "Opening the package $Package"

        $varIO = [System.IO.Compression.ZipFile]::OpenRead($Package)
    }
    catch [System.IO.FileNotFoundException] {
        throw "The package $Package does not exist"
    }
    catch [System.IO.IOException] {
        throw "The file $Package is in use"
    }
    catch [System.UnauthorizedAccessException] {
        throw "You are not authorized to access the $Package"
    }
    catch {
        throw $_.Exception
    }

    #Verifies healthcheck file
    Write-Host "Verifying if package contains $HealthPath..."
    if (! ($varIO.Entries | Where { $_.Name -ieq $HealthPath })) {
        throw "Package does not contain $HealthPath or it's not in the root directory"
    }
    
    #Verifies web config transforms
    Write-Host "Verifying if package contains web config transforms..."
    $match_configs = $varIO.Entries | Where { $_.Name -match "Web.*.config" }
    if (! ($match_configs)) {
        throw "Package does not contain the necessary transforms or they are not in the root directory"
    }
    else {
        if (! ($match_configs | Where { $_.Name -ieq "Web.Release.config" })) {
            throw "Package does not contain Web.Release.config"
        }
    }
    Write-Host "All prerequisites confirmed to be OK!"
    Write-Host " "

    # Unlocks the file
    Write-Debug "Disposing the file variable"
    $varIO.Dispose()
    $varIO = $null
}

<#
# Switch parameters don't work in Octopus because it's passed as -File param
https://connect.microsoft.com/PowerShell/feedback/details/742084/powershell-v2-powershell-cant-convert-false-into-swtich-when-using-file-param
#>
function convertHealthSwitch {
    param(
        [int] $healthSwitch
    )

    return [bool] $healthSwitch
}

<#
# Deals with healthcheck file to stop requests on the server being deployed
#>
function healthSwitch {
    param (
        [string] $HealthPath,
        [string] $Site,
        [string] $Application,
        [int] $HealthDelay=10
    )

    Write-Host "=== Health Switch ==="

    $app_path = ""
    if ($script:obj_deploy.mode -ieq "Website") {
        Write-Host "Checking current Site Path..."

        if (Test-Path "IIS:\Sites\$Site") {
            $app_path = Get-Item "IIS:\Sites\$Site"
        }
        else {
            Write-Host "Couldn't find Website $Site. Skipping this step"
        }
    }
    elseif ($script:obj_deploy.mode -ieq "WebApp") {
        Write-Host "Checking current Application Path..."

        if (Test-Path "IIS:\Sites\$Site\$Application") {
            $app_path = Get-Item "IIS:\Sites\$Site\$Application"
        }
        else {
            Write-Host "Couldn't find Application in $Site/$Application. Skipping this step"
        }
    }

    if ($app_path) {
        $app_path = $app_path.PhysicalPath
        $healthfile_path = "$app_path\$HealthPath"

        if (! (Test-Path($healthfile_path))) {
            Write-Warning "Healthcheck file could not be found in $healthfile_path"
        }
        else {
            try {
                Write-Host "Removing $healthfile_path"
                Remove-Item -Path $healthfile_path -Force

                Write-Host "Waiting $HealthDelay seconds for the load balancer to stop forwarding requests..."
                Sleep $HealthDelay
            }
            catch {
                throw "Error removing $healthfile_path"
            }
        }
    }

    Write-Host " "
}

<#
# Initalises a web deployment
#>
function initWeb {
    printDeployOptions
    checkRequisites -Package $script:obj_deploy.packagePath `
                    -HealthPath $script:obj_deploy.HealthPath
    
    if ($script:obj_deploy.healthSwitch) {
        healthSwitch -HealthPath $script:obj_deploy.HealthPath `
                     -Site $script:obj_deploy.websiteName `
                     -Application $script:obj_deploy.applicationName `
                     -HealthDelay $script:obj_deploy.healthDelay
    }
    initWebsite

    if ($script:obj_deploy.mode -ieq "WebApp") {
        initWebApp
    }
}

<#
# Prints deployment options header
#>
function printDeployOptions {
    $printDeploy = @"
=== Deployment options ===
Mode:                      $($script:obj_deploy.mode)
Package:                   $(Split-Path -Leaf $script:obj_deploy.packagePath)
`nHealthSwitch:              $($script:obj_deploy.healthSwitch)
"@
#Website IP Binding:" $script:obj_deploy["websiteIPBinding"] -ForeGroundColor $fcDEPLOYOPTIONSEXT
    
    if ($script:obj_deploy.healthSwitch) {
        $printDeploy += @"
`nHealthCheck File:          $($script:obj_deploy.HealthPath)
HealthCheck Delay:         $($script:obj_deploy.healthDelay)
"@
}

    $printDeploy += @"
`n--------
Website Name:              $($script:obj_deploy.websiteName)
Website Path:              $($script:obj_deploy.websitePhysicalPath)
Website App Pool Name:     $($script:obj_deploy.websitePoolName)
Website Protocol:          $($script:obj_deploy.websiteProtocol)
Website Port:              $($script:obj_deploy.websitePort)
Website Host Binding:      $($script:obj_deploy.websiteHost)
"@

    if ($script:obj_deploy.mode -eq "WebApp") {
        $printDeploy += @"
`n--------
Application Name:          $($script:obj_deploy.applicationName)
Application Path:          $($script:obj_deploy.applicationPhysicalPath)
Application Pool Name:     $($script:obj_deploy.applicationPoolName)
"@
    }

    Write-Host $printDeploy -ForeGroundColor $fcDEPLOYOPTIONSEXT
    Write-Host " "
}

<#
# Deploys IIS website
#>
function initWebsite {
    # Website tasks
    Write-Host "=== Website Deployment ==="
    createFolder -Path $script:obj_deploy.websitePhysicalPath
    Write-Host " "
    createAppPool -Name $script:obj_deploy.websitePoolName `
                  -ManagedVersion $script:obj_deploy.websitePoolNetVersion `
                  -IdentityType $script:obj_deploy.websitePoolType `
                  -IdentityUser $script:obj_deploy.websitePoolUsername `
                  -IdentityPass $script:obj_deploy.websitePoolPassword
    Write-Host " "
    createWebsite -Name $script:obj_deploy.websiteName `
                  -Path $script:obj_deploy.websitePhysicalPath `
                  -AppPoolName $script:obj_deploy.websitePoolName `
                  -Protocol $script:obj_deploy.websiteProtocol `
                  -IPBinding $script:obj_deploy.websiteIPBinding `
                  -Port $script:obj_deploy.websitePort `
                  -HostHeader $script:obj_deploy.websiteHost
    Write-Host " "
}

<#
# Deploys IIS application
#>
function initWebApp {
    Write-Host "=== WebApplication Deployment ==="
    createFolder -Path $script:obj_deploy.applicationPhysicalPath
    Write-Host " "
    createAppPool -Name $script:obj_deploy.applicationPoolName `
                  -ManagedVersion $script:obj_deploy.applicationPoolNetVersion `
                  -IdentityType $script:obj_deploy.applicationPoolType `
                  -IdentityUser $script:obj_deploy.applicationPoolUsername `
                  -IdentityPass $script:obj_deploy.applicationPoolPassword
    Write-Host " "
    createWebApp -Name $script:obj_deploy.applicationName `
                 -ParentSite $script:obj_deploy.websiteName `
                 -Path $script:obj_deploy.applicationPhysicalPath `
                 -PoolName $script:obj_deploy.applicationPoolName
    Write-Host " "
}

<#
# Finalizes the deployment
# 1. finalizeWebApp
# 2. Reports total deployment time
## Gets $obj_deploy from Octopus
#>
function finalizeDeploy {
    $script:obj_deploy = convertOctoVarsObj
    
    finalizeWeb
    
    [datetime] $start_time = (getVar -Name "deployStartTime")
    $end_time = (Get-Date)

    Write-Host "----------------------------------"
    Write-Host "Deployment completed at $($end_time.ToString($DATEFORMAT))" -ForeGroundColor $fcDEPLOYHIGHLIGHT
    $time_elapsed = New-TimeSpan $start_time $end_time
    Write-Host " "
    Write-Host ("Total deployment time {0:hh\:mm\:ss\.ff}" -f $time_elapsed.Duration()) -ForegroundColor $fcDEPLOYHIGHLIGHT
    
    #
    # Re-add when variables between modules is fixed
    #
    #reportAlerts
}

<#
# Finalize the deployment
# 1. Removes the remaining web configs
# 2. Prints application URL
#>
function finalizeWeb {
    # Removes the remaining Web.configs
    $remove_path = ""
    if ($script:obj_deploy.mode -ieq "Website") {
        $remove_path = $script:obj_deploy.websitePhysicalPath
    }
    elseif ($script:obj_deploy.mode -ieq "WebApp") {
        $remove_path = $script:obj_deploy.applicationPhysicalPath
    }
    removeWebConfigs $remove_path

    # Reports app urls
    Write-Host " "
    Write-Host "Application URLs:" -ForeGroundColor $fcDEPLOYSUCCESS
    getAppURL -WebsiteName "$($script:obj_deploy.websiteName)" -AppName "$($script:obj_deploy.applicationName)"
}