<#
.SYNOPSIS
    Executes Hindsight forensic analysis against browser profiles on the target endpoint.

.DESCRIPTION
    This script orchestrates the Hindsight browser forensic tool execution. It performs
    four sequential phases:

    1. User Profile Identification - Resolves the target Windows user profile, either
       from an explicit username parameter or by auto-discovering the currently logged-in user.

    2. Browser Data Path Resolution - Locates the browser's User Data directory within
       the resolved user profile based on the specified browser type.

    3. Profile Detection - Enumerates browser profiles (Default, Profile 1, Profile 2, etc.)
       within the browser data directory.

    4. Hindsight Execution - Launches Hindsight against each detected profile in
       fire-and-forget mode. Artifact verification is handled by downstream workflow steps.

    The script guarantees JSON output for SOAR workflow integration, capturing any
    errors that occur without interrupting the automation pipeline. If any phase fails,
    subsequent phases are skipped to prevent cascading errors.

.PARAMETER json_input
    JSON string containing the configuration object.
    Required fields:
        - working_directory_path: Absolute path where Hindsight output artifacts will be stored.
        - hindsight_executable_path: Path to the Hindsight executable.
        - output_format: Output format for Hindsight (e.g., xlsx, sqlite, jsonl).
        - target_browser: Target browser name (Google Chrome, Microsoft Edge, Brave).
        - target_hostname: Endpoint hostname for artifact naming.
    Optional fields:
        - target_username: Specific Windows username to target. If omitted, auto-discovers
                           the currently logged-in user.

.OUTPUTS
    JSON object with the following properties:
        - has_processing_errors: Boolean indicating if any errors occurred.
        - target_browser: The target browser name.
        - target_hostname: The endpoint hostname.
        - resolved_username: The resolved Windows username.
        - detected_browser_profiles: Array of detected browser profile names.
        - output_artifact_paths: Array of expected output file paths.
        - execution_timestamp: UTC timestamp used in artifact naming.
        - working_directory_path: The configured working directory path.
        - exception_messages: Array of error messages (only present if errors occurred).

.EXAMPLE
    $params = @{
        working_directory_path = "C:\Temp\Hindsight"
        hindsight_executable_path = "C:\Tools\hindsight.exe"
        output_format = "xlsx"
        target_browser = "Google Chrome"
        target_hostname = "WORKSTATION01"
    } | ConvertTo-Json
    .\hindsight_processing.ps1 -json_input $params
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$json_input
)

$ErrorActionPreference = 'Stop'

# Clear all variables to prevent stale values from previous session runs
$config                = $null
$working_dir_path      = $null
$hindsight_exe_path    = $null
$output_format         = $null
$target_browser        = $null
$target_hostname       = $null
$target_username       = $null
$execution_timestamp   = $null
$browser_data_path     = $null
$resolved_username     = $null
$user_profile_path     = $null
$windows_user_profile  = $null
$profile_directories   = $null
$detected_profiles     = @()
$output_artifact_paths = @()
$exception_messages    = @()

# Parse the JSON input and extract configuration parameters
try {
    $config = $json_input | ConvertFrom-Json
    $working_dir_path = $config.working_directory_path
    $hindsight_exe_path = $config.hindsight_executable_path
    $output_format = $config.output_format
    $target_browser = $config.target_browser
    $target_hostname = $config.target_hostname
    $target_username = $config.target_username
} catch {
    $exception_messages += $_.Exception.Message
}

# Generate UTC timestamp for consistent artifact naming across profiles
$execution_timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH-mm")

# Mapping of supported browsers to their User Data directory locations
$browser_path_lookup = @{
    "Google Chrome"  = "AppData\Local\Google\Chrome\User Data"
    "Microsoft Edge" = "AppData\Local\Microsoft\Edge\User Data"
    "Brave"          = "AppData\Local\BraveSoftware\Brave-Browser\User Data"
}

# -----------------------------------------------------------------------------
# Phase 1: User Profile Identification
# Resolves target user from explicit parameter or auto-discovers logged-in user
# -----------------------------------------------------------------------------
if ($exception_messages.Count -eq 0) {
    try {
        if (-not [string]::IsNullOrWhiteSpace($target_username)) {
            # Explicit username provided - locate matching Windows user profile
            $windows_user_profile = Get-CimInstance Win32_UserProfile | Where-Object {
                ($_.LocalPath -split '\\')[-1] -eq $target_username
            } | Select-Object -First 1

            if (-not $windows_user_profile) {
                throw "User profile not found: $target_username"
            }
            $user_profile_path = $windows_user_profile.LocalPath
            $resolved_username = $target_username
        } else {
            # No username specified - auto-discover currently logged-in user
            $resolved_username = (Get-CimInstance Win32_ComputerSystem).UserName -replace '^.+\\', ''
            $user_profile_path = (Get-CimInstance Win32_UserProfile | Where-Object {
                $_.LocalPath -like "*\$resolved_username"
            }).LocalPath
        }

        if (-not (Test-Path $user_profile_path)) {
            throw "User profile path does not exist: $user_profile_path"
        }
    } catch {
        $exception_messages += $_.Exception.Message
    }
}

# -----------------------------------------------------------------------------
# Phase 2: Browser Data Path Resolution
# Constructs and validates the path to browser's User Data directory
# -----------------------------------------------------------------------------
if ($exception_messages.Count -eq 0) {
    try {
        $browser_data_path = Join-Path -Path $user_profile_path -ChildPath $browser_path_lookup[$target_browser]

        if (-not (Test-Path $browser_data_path)) {
            throw "$target_browser data not found at: $browser_data_path"
        }
    } catch {
        $exception_messages += $_.Exception.Message
    }
}

# -----------------------------------------------------------------------------
# Phase 3: Profile Detection
# Enumerates browser profiles matching Default or Profile N naming convention
# -----------------------------------------------------------------------------
if ($exception_messages.Count -eq 0) {
    try {
        $profile_directories = Get-ChildItem -Path $browser_data_path -Directory |
            Where-Object { $_.Name -match '^Default$|^Profile\s\d+$' }

        if ($profile_directories.Count -eq 0) {
            throw "No browser profiles found in: $browser_data_path"
        }

        $detected_profiles = @($profile_directories | ForEach-Object { $_.Name })
    } catch {
        $exception_messages += $_.Exception.Message
    }
}

# -----------------------------------------------------------------------------
# Phase 4: Hindsight Execution (Fire-and-Forget)
# Launches Hindsight process for each detected profile without waiting
# -----------------------------------------------------------------------------
if ($exception_messages.Count -eq 0) {
    # Normalize paths and names for safe file system usage
    $normalized_exe_path = $hindsight_exe_path -replace "/", "\\"
    $safe_browser_name = $target_browser -replace "\s", "-"

    foreach ($profile_name in $detected_profiles) {
        $profile_source_path = Join-Path $browser_data_path $profile_name
        $safe_profile_name = $profile_name -replace "\s", "-"

        # Construct output path: {working_dir}/{hostname}-{browser}-{profile}-{timestamp}.{format}
        $output_base_path = Join-Path $working_dir_path "${target_hostname}-${safe_browser_name}-${safe_profile_name}-${execution_timestamp}"
        $output_file_path = "$output_base_path.$output_format"

        try {
            Start-Process -FilePath $normalized_exe_path `
                -ArgumentList "-i `"$profile_source_path`" -o `"$output_base_path`" -f $output_format -t UTC" `
                -NoNewWindow

            $output_artifact_paths += $output_file_path
        } catch {
            $exception_messages += $_.Exception.Message
        }
    }
}

# -----------------------------------------------------------------------------
# Build Result Object
# Assembles output for SOAR workflow consumption with all relevant metadata
# -----------------------------------------------------------------------------
$script_result = [PSCustomObject]@{
    has_processing_errors     = $exception_messages.Count -gt 0
    target_browser            = $target_browser
    target_hostname           = $target_hostname
    resolved_username         = $resolved_username
    detected_browser_profiles = $detected_profiles
    output_artifact_paths     = $output_artifact_paths
    execution_timestamp       = $execution_timestamp
    working_directory_path    = $working_dir_path
}

# Append exception details only when errors occurred
if ($exception_messages.Count -gt 0) {
    $script_result | Add-Member -NotePropertyName "exception_messages" -NotePropertyValue $exception_messages
}

$script_result | ConvertTo-Json -Depth 2
