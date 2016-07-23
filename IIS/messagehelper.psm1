<#
# Description: Handles errors and messages
#
# @Version: 1.0.3
#>

$global:alert_event_count=0

function writeAlert {
    param (
        [string] $Message
    )

    Write-Host "WARNING: $Message" -ForeGroundColor DarkMagenta
    $global:alert_event_count += 1
}

# Reports the number of alerts
function reportAlerts {
    if ($global:alert_event_count -gt 0) {
        Write-Host "`nWARNING: Script finished with $global:alert_event_count alerts" -ForegroundColor DarkMagenta
    }
}