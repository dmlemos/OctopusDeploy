<#
# Description: Octopus functions
#
# @Version: 1.0.3
#>

#region Configuration
$ErrorActionPreference = "Stop"

$WarningPreference = "Continue"
$VerbosePreference = "Continue"
#endregion

# Uses consoleMode var to set the variables for either Octopus Deploy or console. Inputs the arguments directly to the command
## If storing array or hashtables, consider converting to PSObject, else it won't work
function setVar {
    if ($global:console_Mode) {
        Set-Variable @Args -Scope Script
        
        Write-Debug "Variable $($Args[1]) set successfully"
    }
    else {
        try {
            # Sets variable in both environments to be used in the current and next steps
            Set-Variable @Args -Scope Script
            Set-OctopusVariable @Args

            Write-Debug "Octopus variable $($Args[1]) set successfully"
        }
        catch {
            throw "Couldn't set the Octopus Deploy Variable. Parameters: { $Args }"
        }
    }
}

# Tries to get the variable from the shell, else gets it from Octopus Deploy
# Always cast when getting variables from Octopus Deploy, because they are always stored in string
function getVar {
    param (
        [string] $Name,
        [switch] $Verbose
    )

    Write-Debug "Gettting variable $Name..."

    $var = Get-Variable -Name $Name -ErrorAction Ignore
    if ($global:console_Mode -and $var) {
        return $var.Value
    }
    else {
        $octopus_var = $OctopusParameters["$Name"]
        return $octopus_var
    }
}

# Converts deployment parameters to octopus variables
# Attaches a specific ID to the variable to identify it later
function convertVarsOcto {
    param (
        [hashtable] $Params
    )

    Write-Debug "Setting <ID>DeploymentConfiguration variables in Octopus Deploy"

    # Uses a unique ID to identify internal parameters
    foreach ($_param in $Params.GetEnumerator()) {
        setVar -Name "34829639DeploymentConfiguration$($_param.Key)" -Value $_param.Value
    }
}

# Converts all the deployment configuration variables to a deployment object
function convertOctoVarsObj {
    Write-Debug "[convertOctoVarsObj] Getting <ID>DeploymenConfiguration variables from Octopus Deploy"
    
    $all_params = @{}

    $OctopusParameters.GetEnumerator() | Where-Object { $_.Key -match "34829639DeploymentConfiguration*" } | % { 
        $name = $_.Key.Replace("34829639DeploymentConfiguration", "")
        $value = $_.Value
        
        $all_params.Add($name, $value)
    }

    $script:obj_deploy = $null
    $script:obj_deploy = New-Object PSCustomObject -Property $all_params
    $script:obj_deploy.PSObject.TypeNames.Insert(0,'DeploymentConfiguration')

    return $script:obj_deploy
}