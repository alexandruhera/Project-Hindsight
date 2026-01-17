<#
.SYNOPSIS
    Prepares the remote environment for Hindsight forensic analysis.

.DESCRIPTION
    Ensures the working directory is clean and exists, preparing the system for
    the subsequent tool deployment and execution phases.

.PARAMETER json_input
    A JSON string containing configuration parameters.
    Required field: 'forensic_analysis_path' (string).

.OUTPUTS
    JSON string containing:
    - has_processing_errors (boolean)
    - forensic_analysis_path (string)
    - exception_messages (array of strings, if errors occur)
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$json_input
)

$ErrorActionPreference = 'Stop'

# Initialize state
$exception_messages = @()
$json_data = $json_input | ConvertFrom-Json
$forensic_analysis_path = $json_data.forensic_analysis_path

try {
    # Ensure the forensic analysis directory is clean and exists
    if (Test-Path -Path $forensic_analysis_path) {
        Remove-Item -Path $forensic_analysis_path -Recurse -Force
    }
    New-Item -Path $forensic_analysis_path -ItemType Directory -Force | Out-Null
} catch {
    $exception_messages += $_.Exception.Message
}

# Output Construction
$has_processing_errors = $exception_messages.Count -gt 0

$json_output = [PSCustomObject]@{
    "has_processing_errors"  = $has_processing_errors
    "forensic_analysis_path" = $forensic_analysis_path
}

if ($has_processing_errors) {
    $json_output | Add-Member -NotePropertyName "exception_messages" -NotePropertyValue $exception_messages
}

$json_output | ConvertTo-Json -Depth 2
