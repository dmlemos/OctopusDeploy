<#
# Description: Common utility functions
#
# @Version: 1.0.0
#>

#region Configuration
$ErrorActionPreference = "Stop"

$WarningPreference = "Continue"
$VerbosePreference = "Continue"
#endregion

# Merges new hashtable with old one, replacing them
function mergeHashTables {
    param (
        [hashtable] $ht_old,
        [hashtable] $ht_new
    )

    try {
        Write-Debug "Merging hashtables..."

        $ht_old.GetEnumerator() | ForEach {
            if (! $ht_new.ContainsKey($_.Key))
            {
                $ht_new.Add($_.Key, $_.Value)
            }
        }
    
        Write-Debug "Finishing merging... returned value"
    }
    catch {
        throw "Error merging hashtables `n$($_.Exception.Message)"
    }

    return $ht_new
}