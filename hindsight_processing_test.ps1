<#
.SYNOPSIS
    TEST VERSION: Executes Hindsight forensic analysis with hardcoded test values.

.DESCRIPTION
    This is a test version of hindsight_processing.ps1 with hardcoded values:
    - forensic_analysis_path: C:\hindsight
    - target_username: alexa
#>

# Enforce strict variable checking
$ErrorActionPreference = 'Stop'

# -------------------------------------------------------------------------
# HARDCODED TEST VALUES
# -------------------------------------------------------------------------
$forensic_analysis_path = "C:\hindsight"
$forensic_tool_path     = "C:\hindsight\hindsight.exe"
$output_format          = "xlsx"
$selected_browser       = "Google Chrome"
$system_hostname        = $env:COMPUTERNAME
$target_username        = "alexa"

# -------------------------------------------------------------------------
# Initialize State Variables
# -------------------------------------------------------------------------
$browser_profile_names   = @()
$browser_profile_paths   = @()
$resolved_user_data_path = $null
$analysis_timestamp      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH-mm")
$forensic_results        = @()

$has_processing_errors   = $false
$exception_messages      = @()

# -------------------------------------------------------------------------
# Configuration: Standard Browser Locations
# -------------------------------------------------------------------------
$browser_paths = @{
    "Google Chrome"  = "AppData\Local\Google\Chrome\User Data"
    "Microsoft Edge" = "AppData\Local\Microsoft\Edge\User Data"
    "Brave"          = "AppData\Local\BraveSoftware\Brave-Browser\User Data"
}

# -------------------------------------------------------------------------
# Phase 1: User Profile Identification
# -------------------------------------------------------------------------
try {
    Write-Host "Targeting user: $target_username"
    # Attempt to find the profile path by strictly matching the username part of the path
    $target_user_object = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { 
        ($_.LocalPath -split '\\')[-1] -eq $target_username 
    } | Select-Object -First 1

    if (-not $target_user_object) {
        throw "Target user profile not found for username: $target_username"
    }
    $user_profile_path = $target_user_object.LocalPath
    Write-Host "Found profile path: $user_profile_path"

    # Validate the profile path exists
    if (-not (Test-Path $user_profile_path)) { 
        throw "The user's local profile path does not exist: $user_profile_path"
    }
} catch {
    $exception_messages += $_.Exception.Message
}

$has_processing_errors = [bool]($exception_messages.Count)

# -------------------------------------------------------------------------
# Phase 2: Browser Data Path Resolution
# -------------------------------------------------------------------------
if (-not $has_processing_errors) {
    try {
        $browser_user_data_path = Join-Path -Path $user_profile_path -ChildPath $browser_paths[$selected_browser]

        if (-not (Test-Path $browser_user_data_path)) { 
            throw "The selected browser's data path does not exist: $browser_user_data_path"
        }
        $resolved_user_data_path = $browser_user_data_path
        Write-Host "Browser data path: $resolved_user_data_path"
    } catch {
        $exception_messages += "An error occurred when checking the browser profile path: $($_.Exception.Message)"
    }
}

$has_processing_errors = [bool]($exception_messages.Count)

# -------------------------------------------------------------------------
# Phase 3: Profile Detection
# -------------------------------------------------------------------------
if (-not $has_processing_errors) {
    try {
        # Scan for 'Default' or 'Profile X' folders
        $detected_profiles = Get-ChildItem -Path $resolved_user_data_path -Directory | Where-Object { $_.Name -match '^Default$|^Profile\s\d+$' }

        foreach ($profile_entry in $detected_profiles) {
            $browser_profile_names += $profile_entry.Name
            $browser_profile_paths += $profile_entry.FullName
            Write-Host "Detected Profile: $($profile_entry.Name)"
        }
    } catch {
        $exception_messages += "An error occurred when attempting to access the browser profile path: $($_.Exception.Message)"
    }
}

# -------------------------------------------------------------------------
# Phase 4: Forensic Execution (Fire-and-Forget)
# -------------------------------------------------------------------------
$has_processing_errors = [bool]($exception_messages.Count)

if (-not $has_processing_errors) {
    foreach ($index in 0..($browser_profile_names.Count - 1)) {
        $source_profile_path        = $browser_profile_paths[$index]
        $cleaned_profile_name       = $browser_profile_names[$index] -replace "\s", "-"
        $cleaned_browser_name       = $selected_browser -replace "\s", "-"
        $cleaned_forensic_tool_path = $forensic_tool_path -replace "/", "\\"

        # Construct unique output path
        $forensic_output_base = Join-Path $forensic_analysis_path "${system_hostname}-${cleaned_browser_name}-${cleaned_profile_name}-${analysis_timestamp}"
        $forensic_output_path = "$forensic_output_base.$output_format"

        try {
            Write-Host "Launching Hindsight for profile: $cleaned_profile_name"
            # Launch Hindsight without waiting
            # Note: In a real local test, you might want to add -Wait to see results immediately
            Start-Process -FilePath $cleaned_forensic_tool_path `
                -ArgumentList "-i `"$source_profile_path`" -o `"$forensic_output_base`" -f $output_format -t UTC" `
                -NoNewWindow 

            # Optimistically add the path to results for downstream collection
            $forensic_results += $forensic_output_path
        } catch {
            $exception_messages += $_.Exception.Message
        }
    }
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
        "has_processing_errors" = $has_processing_errors
        "user_data_path"        = $resolved_user_data_path
        "browser_profile_names" = $browser_profile_names
        "browser_profile_paths" = $browser_profile_paths
        "forensic_results"      = $forensic_results
        "analysis_timestamp"    = $analysis_timestamp
    }
}

$json_output | ConvertTo-Json -Depth 2
