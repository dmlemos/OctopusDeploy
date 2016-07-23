# Description
### Please note this repository is for archive only.

Scripts to deploy IIS applications. Designed for OctopusDeploy, but also works when running from the console.

# Requirements
* IIS
* Powershell v4

# How to Use
Create an optional `healthcheck.aspx` file, depending on your load balancer can simple return 'Up':
```ASP
<!DOCTYPE html>
<html>
<body>
<!-- YOUR CODE
#
<%
Response.Write("Up")
%>
#
END OF YOUR CODE -->
</body>
</html>
```
You'd want to check for all the dependencies app needs to work. E.g. database, caching, etc.

Generate a nuget package with your application (ideally using CI).

### Website parameters

Name                    | Description
----------------------- | -------------------------------
Mode                    | 'Website'. See below for differences
WebsiteName             | Name for website
WebsitePhysicalPath     | Physical path where the website code is
WebsitePoolName         | IISAppPool name to assign
WebsiteProtocol         | Default: HTTP
WebsiteIPBinding        | Default: *
WebsitePort             | Default: 80
WebsiteHost             | IIS host header
WebsitePoolType         | ApplicationPool Identity type
WebsitePoolUsername     | If empty default 'Application Pool Identity' will be used.
WebsitePoolPassword     | Password for username above
websitePoolNetVersion   | .NET Framework to use
PackagePath             | Path on the disk for nuget package


### WebApplication parameters

Name                      | Description
------------------------- | -------------------------------
Mode                      | 'WebApp'. See below for differences
ApplicationName           | Name for application
ApplicationPhysicalPath   | Physical Path where the webapp code is
ApplicationPoolName       | IISAppPool name to assign
ApplicationPoolType       | ApplicationPool Identity type
ApplicationPoolUsername   | If empty default 'Application Pool Identity' will be used.
ApplicationPoolPassword   | Password for username above
applicationPoolNetVersion | .NET Framework to use
PackagePath               | Path on the disk for nuget package
HealthPath                | Name of healthfile configured in LB
HealthDelay               | Delay (in seconds) to wait after taking app down. Basically waiting until LB removes website from pool

## Octopus Deploy
This is an example of how to configure in Octopus Deploy.
Use with **'Deploy Process Step'** or alternatively configure version control.

``Import-Module`` is required on pre and post parts of the deployment because they are treated as new sessions in Octopus Deploy.

## Pre-deployment step
```Powershell
Import-Module .\deployapp.psm1 -DisableNameChecking -Global -Force

# Deploy website
initDeploy -Mode "Website" `
           -WebsiteName "mywebsite1" `
           -WebsitePhysicalPath "C:\inetpub\wwwroot\mywebsite1\_Root" `
           -WebsitePoolName "mywebsite1" `
           -WebsiteHost "mywebsite1.com" `
           -PackagePath <packageID>

# Deploy webapp
initDeploy -Mode "WebApp" `
           -WebsiteName "mywebsite1" `
           -WebsitePhysicalPath "C:\inetpub\wwwroot\mywebsite1\_Root" `
           -WebsitePoolName "mywebsite1" `
           -WebsiteHost "mywebsite1.com" `
           -ApplicationName "myapp1" `
           -ApplicationPhysicalPath "C:\inetpub\wwwroot\mywebsite1\myapp1" `
           -ApplicationPoolName "myapp1" `
           -PackagePath <packageID>
           -HealthPath "healthcheck.aspx" `
           -HealthDelay 10
```

## Post-deployment step
Cleanup and reports 
```Powershell
Import-Module .\deployapp.psm1 -DisableNameChecking -Global -Force

finalizeDeploy
```

# Console (running manually)
Create a file, e.g. **main.ps1** with the following contents:
```Powershell
param (
    [switch] $DEBUG=$false
)

Import-Module .\IIS\deployapp.psm1 -DisableNameChecking -Global -Force

# Replace parameters with your user case
initDeploy <parameters>

if ($DEBUG) {
    ## Pause the deployment
    Write-Host "Press any key to continue..."
    $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
}

finalizeDeploy

# Removes Octopus variables
try {
    Remove-Variable -Name Octopus*
}
catch {}
```

## Debug
Following built-in variables can be configured:
- $VerbosePreference
- $DebugPreference

[Click here for information about Preference Variables](https://technet.microsoft.com/en-us/library/hh847796(v=wps.630).aspx)