<#
# Description: IIS functions
#
# @Version: 1.0.5
#>

Import-Module WebAdministration -ErrorAction Stop

#region Configuration
$ErrorActionPreference = "Stop"

$WarningPreference = "Continue"
$VerbosePreference = "Continue"
#endregion

function createAppPool {
    param(
        [string] $Name,
        [string] $ManagedVersion,
        [string] $IdentityType,
        [string] $IdentityUser,
        [string] $IdentityPass
    )

    Write-Host "Checking if Application Pool $Name exists..."

    if (! $(Test-Path "IIS:\AppPools\$Name")) {
        #Write-Host "Application Pool $Name doesn't exist"
        Write-Host "Creating Application Pool $Name..."

        try {
            New-WebAppPool -Name $Name | Out-Null

            $iis_path = "IIS:\AppPools\$Name"

            if (! ($ManagedVersion.Trim() -eq "")) {
                Set-ItemProperty $iis_path -Name managedRuntimeVersion -Value $ManagedVersion
            }
            else {
                Write-Verbose "Application Pool .NET Version not specified. Using default from server"
            }

            if (! ($IdentityType.Trim() -eq "")) {
                # Identity type will always be text, except when there's a username and password specified
                # For that case will be 3. If it fails to convert to int means is text
                try {
                    $val_pool_identity_type = [int]$IdentityType
                }
                catch {
                    $val_pool_identity_type = $IdentityType
                }

                Set-ItemProperty $iis_path -Name processModel -Value @{identityType=$val_pool_identity_type}
                if ($val_pool_identity_type -eq 3) {
                    Set-ItemProperty $iis_path -Name processModel -Value @{userName=$IdentityUser}
                    Set-ItemProperty $iis_path -Name processModel -Value @{password=$IdentityPass}
                }
            }
            else {
                Write-Verbose "Application Pool Identity not specified. Using default 'ApplicationPoolIdentity'"
            }

            Write-Host "ApplicationPool $Name created successfully"

            Write-Host "Checking if ApplicationPool has started..."
            $app_status = Get-WebAppPoolState -Name $Name
            if (! ($app_status -match "Started")) {
                Write-Host "Application Pool has not been started"
                Write-Host "Starting Application Pool $Name..."
                
                try {
                    Start-WebAppPool -Name $Name | Out-Null

                    Write-Host "Application started successfully"
                }
                catch {
                    Write-Warning "Couldn't start the Application Pool $Name. Please start it manually!"
                }
            }
        }
        catch {
            throw "Error creating the Application Pool $Name"
        }
    }
    else {
        Write-Host "Application Pool $Name already exists. Skipping this step"
    }
}

function createWebsite {
    param (
        [string] $Name,
        [string] $Path,
        [string] $AppPoolName,
        [string] $Protocol,
        [string] $IPBinding,
        [int] $Port,
        [string] $HostHeader
    )

    Write-Host "Checking if Website $Name already exists..."

    if (! $(Get-Website | Where { $_.Name -eq "$Name" })) {
        #Write-Host "Website $Name doesn't exist"

        $cur_binding = "${IPBinding}:${Port}:$HostHeader"
        Write-Host "Checking if Website with binding '$cur_binding' already exists..."
        if (! $(Get-WebBinding | Where { $_.bindingInformation -eq $cur_binding})) {

            #Write-Host "Website binding '$cur_binding' doesn't exist"
            Write-Host "Creating Website $Name..."

            try {
                New-Website -Name $Name -PhysicalPath $Path | Out-Null

                $iis_path = "IIS:\Sites\$Name"

                Set-ItemProperty $iis_path -Name applicationPool -Value $AppPoolName
                Set-ItemProperty $iis_path -Name bindings -Value @{protocol="${Protocol}";bindingInformation="$cur_binding"}

                Write-Host "Website $Name created successfully"
            }
            catch {
                throw "Error creating the Website $Name"
            }

            $website_status = getWebSiteStatus $Name
            if (! ($website_status -match "Started")) {
                Write-Host "Website has not been started"
                Write-Host "Starting website $Name..."

                try {
                    Start-Website -Name $Name | Out-Null

                    Write-Host "Website started successfully"
                }
                catch {
                    Write-Warning "Couldn't start the Website $Name. Please start it manually!"
                }
            }
        }
        else {
            throw "Website $Name has confliting bindings:`n $cur_binding"
        }
    }
    else {
        Write-Host "Website $Name already exists. Skipping this step"
    }
}

function createWebApp {
    param (
        [string] $Name,
        [string] $ParentSite,
        [string] $Path,
        [string] $PoolName
    )

    Write-Host "Checking if Web Application $Name already exists..."

    if (! $(Get-WebApplication -Site $ParentSite -Name $Name)) {
        #Write-Host "Web Application $Name doesn't exist"
        Write-Host "Creating Web Application $Name..."

        try {
            New-WebApplication -Name $Name -Site $ParentSite -PhysicalPath $Path | Out-Null

            $iis_path = "IIS:\Sites\$ParentSite\$Name"
            Set-ItemProperty $iis_path -Name applicationPool -Value $PoolName

            Write-Host "WebApplication $Name created successfully"
        }
        catch {
            throw "Error creating the Web Application $Name"
        }
    }

    else {
        Write-Host "Web Application $ParentSite/$Name already exists. Skipping this step"
    }
}

function getAppURL {
    param (
        [string] $WebsiteName,
        [string] $AppName=""
    )

    try {
        # Gets binding object from IIS
        $get_binding = Get-WebBinding -Name $WebsiteName

        # Gets binding protocol
        [array] $binding_protocol = $get_binding.protocol

        # Gets other binding information
        [array] $binding_info = $get_binding.bindingInformation

        $app_bindings = @()
        $i = 0
        $binding_info | ForEach {
            [int] $cur_port = $_.Substring($_.IndexOf(":")+1, $_.LastIndexOf(":")-2)
            $cur_host = $_.Substring($_.LastIndexOf(":")+1, $_.Length-$_.LastIndexOf(":")-1)

            if ($cur_port -eq 80) {
                $app_bindings += $binding_protocol[$i] + "://" + $cur_host + "/" + $AppName
            }
            else {
                $app_bindings += $binding_protocol[$i] + "://" + $cur_host + ":" + $cur_port + "/" + $AppName
            }

            $i++
        }   
    }
    catch {
        Write-Warning "Could not get app urls"
    }

    return $app_bindings
}

function getWebSiteStatus {
    param (
        [string] $Name
    )

    try {
        $site_status = Get-Website | Where { $_.Name -eq $Name } | Select-Object -ExpandProperty State
    }
    catch {
        Write-Warning "Couldn't get the status for website $Name" + "`n $_"
    }

    return $site_status
}