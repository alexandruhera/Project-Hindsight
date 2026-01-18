<#
.SYNOPSIS
    TEST VERSION: Local testing with hardcoded values.
#>

$ErrorActionPreference = 'Stop'

# Clear all variables to prevent stale values from previous session runs
$working_directory_path    = $null
$hindsight_executable_path = $null
$output_format             = $null
$target_browser            = $null
$target_hostname           = $null
$target_username           = $null
$execution_timestamp       = $null
$browser_data_path         = $null
$resolved_username         = $null
$user_profile_path         = $null
$windows_user_profile      = $null
$profile_directories       = $null
$detected_browser_profiles = @()
$output_artifact_paths     = @()
$exception_messages        = @()

# HARDCODED TEST VALUES (comment out to test auto-discovery behavior)
$working_directory_path    = "C:\hindsight"
$hindsight_executable_path = "C:\hindsight\hindsight.exe"
$output_format             = "xlsx"
$target_browser            = "Google Chrome"
$target_hostname           = $env:COMPUTERNAME
$target_username           = "alexa"

# Generate timestamp after variable initialization
$execution_timestamp       = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH-mm")

# Mapping of supported browsers to their User Data directory locations
$browser_path_lookup = @{
    "Google Chrome"  = "AppData\Local\Google\Chrome\User Data"
    "Microsoft Edge" = "AppData\Local\Microsoft\Edge\User Data"
    "Brave"          = "AppData\Local\BraveSoftware\Brave-Browser\User Data"
}

# -------------------------------------------------------------------------
# Phase 1: User Profile Identification
# Resolves target user from explicit parameter or auto-discovers logged-in user
# -------------------------------------------------------------------------
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

# -------------------------------------------------------------------------
# Phase 2: Browser Data Path Resolution
# -------------------------------------------------------------------------
if ($exception_messages.Count -eq 0) {
    try {
        $browser_data_path = Join-Path -Path $user_profile_path -ChildPath $browser_path_lookup[$target_browser]

        if (-not (Test-Path $browser_data_path)) {
            throw "$target_browser data not found: $browser_data_path"
        }
    } catch {
        $exception_messages += $_.Exception.Message
    }
}

# -------------------------------------------------------------------------
# Phase 3: Profile Detection
# -------------------------------------------------------------------------
if ($exception_messages.Count -eq 0) {
    try {
        $profile_directories = Get-ChildItem -Path $browser_data_path -Directory |
            Where-Object { $_.Name -match '^Default$|^Profile\s\d+$' }

        if ($profile_directories.Count -eq 0) {
            throw "No profiles found in: $browser_data_path"
        }

        $detected_browser_profiles = @($profile_directories | ForEach-Object { $_.Name })
    } catch {
        $exception_messages += $_.Exception.Message
    }
}

# -------------------------------------------------------------------------
# Phase 4: Launch Hindsight (Fire-and-Forget)
# -------------------------------------------------------------------------
if ($exception_messages.Count -eq 0) {
    $normalized_exe_path = $hindsight_executable_path -replace "/", "\\"
    $sanitized_browser_name = $target_browser -replace "\s", "-"

    foreach ($profile_name in $detected_browser_profiles) {
        $profile_source_path = Join-Path $browser_data_path $profile_name
        $sanitized_profile_name = $profile_name -replace "\s", "-"

        $output_base_path = Join-Path $working_directory_path "${target_hostname}-${sanitized_browser_name}-${sanitized_profile_name}-${execution_timestamp}"
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

# -------------------------------------------------------------------------
# Build Result Object
# -------------------------------------------------------------------------
$script_result = [PSCustomObject]@{
    has_processing_errors     = $exception_messages.Count -gt 0
    target_browser            = $target_browser
    target_hostname           = $target_hostname
    resolved_username         = $resolved_username
    detected_browser_profiles = $detected_browser_profiles
    output_artifact_paths     = $output_artifact_paths
    execution_timestamp       = $execution_timestamp
    working_directory_path    = $working_directory_path
}

if ($exception_messages.Count -gt 0) {
    $script_result | Add-Member -NotePropertyName "exception_messages" -NotePropertyValue $exception_messages
}

$script_result | ConvertTo-Json -Depth 2
