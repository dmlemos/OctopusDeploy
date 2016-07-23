<#
# Description: I/O functions
#
# @Version: 1.0.3
#>

#region Configuration
$ErrorActionPreference = "Stop"

$WarningPreference = "Continue"
$VerbosePreference = "Continue"
#endregion

# Always creates a folder. If the folder already exists, removes it first and then creates the folder
function ensureFolder {
    param(
        [string] $Path
    )

    if ([String]::IsNullorEmpty($Path)) {
        throw "Cannot create folder because parameter Path is empty"
    }

    Write-Host "Checking if folder $Path exists..."

    if (Test-Path $Path) {
        try {
            Write-Host "Removing $Path..."
            Remove-Item "$Path\*" -Recurse -Force
        }
        catch {
            throw "Couldn't remove the folder $Path"
        }
    }
    
    try {
        Write-Host "Creating folder $Path..."
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "Created folder $Path"
    }
    catch {
        throw "Failed to create the folder $Path"
    }
}

# Creates a folder if it doesn't exist
function createFolder {
    param(
        [string] $Path
    )

    if ([String]::IsNullorEmpty($Path)) {
        exitError "Cannot create folder because parameter Path is empty"
    }

    Write-Host "Checking if folder $Path exists..."

    if (! $(Test-Path $Path)) {
        try {
            Write-Host "Creating folder $Path..."
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Host "Created folder $Path"
        }
        catch {
            exitError "Failed to create the folder $Path"
        }
    }
    else {
        Write-Host "Folder $Path already exists. Skipping this step"
    }
}

# Removes remaining web.config transforms
function removeWebConfigs {
    param (
        [string] $ConfigPath
    )

    Write-Host "Removing unnecessary web config transform files from $ConfigPath..."

    if (Test-Path $ConfigPath) {
        $out_ls = Get-ChildItem -Path $ConfigPath -Filter Web.*.config
        
        if ($out_ls) {
            $out_ls | ForEach-Object {
                Write-Host "Deleting $($_.Name)"
                Remove-Item -Force $_
            }
        
            Write-Host "Web config transform files removed sucessfully"
        }
        else {
            Write-Host "No web config transform files found"
        }
    }
    else {
        Write-Warning "Invalid Web Application path: $ConfigPath"
    }
}