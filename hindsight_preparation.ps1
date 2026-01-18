<#
.SYNOPSIS
    Prepares a clean working directory on the remote endpoint for Hindsight browser forensic analysis.

.DESCRIPTION
    This script initializes the environment required for Hindsight forensic collection.
    It removes any existing artifacts from previous runs and creates a fresh working
    directory to ensure consistent and uncontaminated forensic output.

    The script guarantees JSON output for SOAR workflow integration, capturing any
    errors that occur during preparation without interrupting the automation pipeline.

.PARAMETER json_input
    JSON string containing the configuration object.
    Required fields:
        - working_directory_path: Absolute path where Hindsight artifacts will be stored.

.OUTPUTS
    JSON object with the following properties:
        - has_processing_errors: Boolean indicating if any errors occurred.
        - working_directory_path: The configured working directory path.
        - exception_messages: Array of error messages (only present if errors occurred).

.EXAMPLE
    .\hindsight_preparation.ps1 -json_input '{"working_directory_path": "C:\\Temp\\Hindsight"}'
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$json_input
)

$ErrorActionPreference = 'Stop'

# Clear all variables to prevent stale values from previous session runs
$config             = $null
$working_dir_path   = $null
$exception_messages = @()

try {
    # Parse the JSON input to extract configuration parameters
    $config = $json_input | ConvertFrom-Json
    $working_dir_path = $config.working_directory_path

    # Remove existing working directory to ensure clean state for new collection
    if (Test-Path -Path $working_dir_path) {
        Remove-Item -Path $working_dir_path -Recurse -Force
    }

    # Create fresh working directory for Hindsight output
    New-Item -Path $working_dir_path -ItemType Directory -Force | Out-Null
} catch {
    $exception_messages += $_.Exception.Message
}

# Build the result object for SOAR workflow consumption
$script_result = [PSCustomObject]@{
    has_processing_errors  = $exception_messages.Count -gt 0
    working_directory_path = $working_dir_path
}

# Append exception details only when errors occurred
if ($exception_messages.Count -gt 0) {
    $script_result | Add-Member -NotePropertyName "exception_messages" -NotePropertyValue $exception_messages
}

$script_result | ConvertTo-Json -Depth 2
