<#
.SYNOPSIS
    Prepares the remote environment for Hindsight forensic analysis.

.DESCRIPTION
    This script validates the input JSON, ensures the working directory is clean and exists, 
    and prepares the system for the subsequent tool deployment and execution phases.
    It is designed to be fail-safe, returning structured JSON error messages upon failure.

.PARAMETER json_input
    A JSON string containing configuration parameters.
    Required field: 'forensic_analysis_path' (string).

.OUTPUTS
    JSON string containing:
    - has_processing_errors (boolean)
    - forensic_analysis_path (string)
    - exception_messages (array of strings, if errors occur)

.EXAMPLE
    .hindsight_preparation.ps1 -json_input '{"forensic_analysis_path": "C:\\hindsight"}'
#>

param (
    [Parameter(Mandatory=$true, HelpMessage="JSON input string provided by the SOAR workflow.")]
    [string]$json_input
)

# Enforce strict variable checking and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Initialize state variables
$has_processing_errors = $false
$exception_messages = @()
$forensic_analysis_path = $null

try {
    # -------------------------------------------------------------------------
    # Input Validation
    # -------------------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($json_input)) {
        throw "Input JSON is empty or null."
    }

    $json_data = $json_input | ConvertFrom-Json
    
    if (-not $json_data.forensic_analysis_path) {
        throw "Missing required field: forensic_analysis_path"
    }

    $forensic_analysis_path = $json_data.forensic_analysis_path

    # -------------------------------------------------------------------------
    # Environment Preparation
    # -------------------------------------------------------------------------
    # Ensure the forensic analysis directory is clean and exists
    if (Test-Path -Path $forensic_analysis_path) {
        # Attempt to remove existing directory, handling potential locking issues
        Remove-Item -Path $forensic_analysis_path -Recurse -Force -ErrorAction Stop
    }
    
    # Create the fresh working directory
    New-Item -Path $forensic_analysis_path -ItemType Directory -Force | Out-Null

} catch {
    $exception_messages += $_.Exception.Message
}

# -------------------------------------------------------------------------
# Output Construction
# -------------------------------------------------------------------------
$has_processing_errors = [bool]($exception_messages.Count)

if ($has_processing_errors) {
    $json_output = [PSCustomObject]@{ 
        "has_processing_errors" = $has_processing_errors
        "exception_messages"    = $exception_messages
    }
} else {
    $json_output = [PSCustomObject]@{ 
        "has_processing_errors"  = $has_processing_errors
        "forensic_analysis_path" = $forensic_analysis_path
    }
}

$json_output | ConvertTo-Json -Depth 2
