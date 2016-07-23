param (
	[string] $server
	[string] $apiKey
	[string] $project
)

Clear-Host

# Solves problems when variable is a string and the regex fail
Remove-Variable octo_output

Write-Host "Finding previous releases..."
$octo_output = & .\Octo.exe list-releases `
           --server=$server `
           --apiKey=$apiKey `
           --project=$project

# Checks to see if there are no previous releases
if ($octo_output | Select-String '^Releases(\:|\:(\s+)|\s+)0$') {
    Write-Host "There are no previous releases"
    return
}

# Shows only the version numbers
$octo_output = $octo_output | Select-String '^(\s+)Version\:(\s+|)(\d+).*$'
$octo_output = $octo_output -replace '.*Version(:|)(\s+)'

Write-Host "Listing releases"
$octo_output