<#
.SYNOPSIS
    TEST VERSION: Executes Hindsight forensic analysis with hardcoded test values.

.DESCRIPTION
    Local testing version of hindsight_processing.ps1 with hardcoded values
    and Write-Host output for debugging.
#>

$ErrorActionPreference = 'Stop'

# HARDCODED TEST VALUES
$forensic_analysis_path = "C:\hindsight"
$forensic_tool_path     = "C:\hindsight\hindsight.exe"
$output_format          = "xlsx"
$selected_browser       = "Google Chrome"
$system_hostname        = $env:COMPUTERNAME
$target_username        = "alexa"

# Initialize State
$browser_profile_names   = @()
$browser_profile_paths   = @()
$resolved_user_data_path = $null
$analysis_timestamp      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH-mm")
$forensic_results        = @()
$exception_messages      = @()

# Browser Data Locations
$browser_paths = @{
    "Google Chrome"  = "AppData\Local\Google\Chrome\User Data"
    "Microsoft Edge" = "AppData\Local\Microsoft\Edge\User Data"
    "Brave"          = "AppData\Local\BraveSoftware\Brave-Browser\User Data"
}

# Sanitized names for file output
$cleaned_browser_name = $selected_browser -replace "\s", "-"

# -------------------------------------------------------------------------
# Phase 1: User Profile Identification
# -------------------------------------------------------------------------
try {
    Write-Host "Targeting user: $target_username"

    $target_user_object = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object {
        ($_.LocalPath -split '\\')[-1] -eq $target_username
    } | Select-Object -First 1

    if (-not $target_user_object) {
        throw "Target user profile not found: $target_username"
    }
    $user_profile_path = $target_user_object.LocalPath
    Write-Host "Found profile path: $user_profile_path"

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
        $resolved_user_data_path = Join-Path -Path $user_profile_path -ChildPath $browser_paths[$selected_browser]

        if (-not (Test-Path $resolved_user_data_path)) {
            throw "Browser data path does not exist: $resolved_user_data_path"
        }
        Write-Host "Browser data path: $resolved_user_data_path"
    } catch {
        $exception_messages += $_.Exception.Message
    }
}

# -------------------------------------------------------------------------
# Phase 3: Profile Detection
# -------------------------------------------------------------------------
if ($exception_messages.Count -eq 0) {
    try {
        $detected_profiles = Get-ChildItem -Path $resolved_user_data_path -Directory |
            Where-Object { $_.Name -match '^Default$|^Profile\s\d+$' }

        if ($detected_profiles.Count -eq 0) {
            throw "No browser profiles found in: $resolved_user_data_path"
        }

        foreach ($profile in $detected_profiles) {
            $browser_profile_names += $profile.Name
            $browser_profile_paths += $profile.FullName
            Write-Host "Detected profile: $($profile.Name)"
        }
    } catch {
        $exception_messages += $_.Exception.Message
    }
}

# -------------------------------------------------------------------------
# Phase 4: Forensic Execution (Fire-and-Forget)
# -------------------------------------------------------------------------
if ($exception_messages.Count -eq 0) {
    $cleaned_tool_path = $forensic_tool_path -replace "/", "\\"

    for ($i = 0; $i -lt $browser_profile_names.Count; $i++) {
        $source_path = $browser_profile_paths[$i]
        $cleaned_profile_name = $browser_profile_names[$i] -replace "\s", "-"

        $output_base = Join-Path $forensic_analysis_path "${system_hostname}-${cleaned_browser_name}-${cleaned_profile_name}-${analysis_timestamp}"
        $output_path = "$output_base.$output_format"

        try {
            Write-Host "Launching Hindsight for profile: $cleaned_profile_name"
            Start-Process -FilePath $cleaned_tool_path `
                -ArgumentList "-i `"$source_path`" -o `"$output_base`" -f $output_format -t UTC" `
                -NoNewWindow

            $forensic_results += $output_path
        } catch {
            $exception_messages += $_.Exception.Message
        }
    }
}

# -------------------------------------------------------------------------
# Output Construction
# -------------------------------------------------------------------------
$has_processing_errors = $exception_messages.Count -gt 0

$json_output = [PSCustomObject]@{
    "has_processing_errors"  = $has_processing_errors
    "user_data_path"         = $resolved_user_data_path
    "browser_profile_names"  = $browser_profile_names
    "browser_profile_paths"  = $browser_profile_paths
    "forensic_results"       = $forensic_results
    "analysis_timestamp"     = $analysis_timestamp
    "cleaned_browser_name"   = $cleaned_browser_name
}

if ($has_processing_errors) {
    $json_output | Add-Member -NotePropertyName "exception_messages" -NotePropertyValue $exception_messages
}

$json_output | ConvertTo-Json -Depth 2
