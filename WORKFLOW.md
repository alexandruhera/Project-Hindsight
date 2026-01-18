# Fusion SOAR Workflow Documentation

Comprehensive documentation of the CrowdStrike Fusion SOAR workflow for Hindsight browser forensics collection.

## Workflow Overview

This is an **on-demand workflow** triggered manually by an analyst when browser forensics collection is needed from one or more endpoints.

## Workflow Stages

### Stage 1: Manual Trigger

**Action Type**: Manual Trigger

The workflow begins with a manual trigger initiated by an analyst. The trigger collects initial parameters needed for the collection.

**Trigger Inputs**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `falcon_sensor_id` | string | Yes | CrowdStrike Agent ID (32-char hex) of target endpoint |
| `target_browser` | enum | Yes | Browser to collect (Google Chrome, Microsoft Edge, Brave) |
| `output_format` | enum | Yes | Hindsight output format (xlsx, sqlite, jsonl) |
| `target_username` | string | No | Windows username to target (empty = auto-discover active user) |

---

### Stage 2: Get Device Details

**Action Type**: Falcon SOAR - Get Device Details

Retrieves device information from the Falcon platform using the `falcon_sensor_id` from the trigger.

**Key Output**:
- `platform_name` - Operating system of the target endpoint (Windows, Mac, Linux)
- `hostname` - Device hostname (used for artifact naming and notifications)

---

### Stage 3: Platform Condition Check

**Action Type**: Condition

Evaluates whether the target endpoint is running Windows, as the PowerShell scripts have a Windows dependency.

**Condition Logic**:
```
IF platform_name == "Windows"
    → Continue to Stage 4
ELSE
    → Abort workflow (unsupported platform)
```

**Abort Notification** (optional):
- Notify analyst that collection cannot proceed on non-Windows endpoint

---

### Stage 4: Create Working Directory Variable

**Action Type**: Falcon SOAR - Create Variable

Creates a workflow variable for the working directory path. This approach keeps the directory path configurable without modifying the scripts.

**Variable Created**:
| Variable Name | Value | Purpose |
|---------------|-------|---------|
| `working_directory_path` | `C:\hindsight` (or configured path) | Centralized path management |

**Design Decision**: Using a SOAR variable rather than hardcoding in scripts allows:
- Easy path changes without script modifications
- Environment-specific configurations
- Audit trail of configuration changes

---

### Stage 5: Preparation Script Execution

**Action Type**: RTR - Run Script

Executes `hindsight_preparation.ps1` on the target endpoint.

**Input Mapping**:
| Script Parameter | Source |
|------------------|--------|
| `working_directory_path` | Stage 4 variable |

**Script Actions**:
1. Remove existing working directory (ensures clean slate)
2. Create fresh working directory

**Outputs**:
| Field | Description |
|-------|-------------|
| `has_processing_errors` | Boolean for workflow branching |
| `working_directory_path` | Confirmed path for downstream stages |
| `exception_messages` | Error details if failed |

---

### Stage 6: Preparation Error Check

**Action Type**: Condition

Checks if the preparation script completed successfully.

**Condition Logic**:
```
IF has_processing_errors == false
    → Continue to Stage 7
ELSE
    → Error handling path (notify analyst, abort)
```

---

### Stage 7: Put-File (Deploy Hindsight Binary)

**Action Type**: RTR - Put-File

Uploads the `hindsight.exe` binary to the working directory on the target endpoint.

**Input Mapping**:
| Parameter | Source |
|-----------|--------|
| Target Path | `{working_directory_path}\hindsight.exe` |
| Source File | Pre-uploaded `hindsight.exe` from RTR Put-Files |

**Outputs**:
| Field | Description |
|-------|-------------|
| `hindsight_executable_path` | Full path to deployed binary |

**Prerequisites**:
- `hindsight.exe` must be pre-uploaded to CrowdStrike RTR Put-Files

---

### Stage 8: Processing Script Execution

**Action Type**: RTR - Run Script

Executes `hindsight_processing.ps1` on the target endpoint. This is the core forensics collection stage.

**Input Mapping**:
| Script Parameter | Source |
|------------------|--------|
| `working_directory_path` | Stage 4 variable |
| `hindsight_executable_path` | Stage 7 output |
| `output_format` | Stage 1 trigger input |
| `target_browser` | Stage 1 trigger input |
| `target_hostname` | Stage 2 device details |
| `target_username` | Stage 1 trigger input (optional) |

**Script Actions**:
1. Resolve target user (explicit or auto-discover via Win32_ComputerSystem)
2. Locate browser User Data directory
3. Enumerate browser profiles (Default, Profile 1, Profile 2, etc.)
4. Launch Hindsight for each profile (fire-and-forget mode)

**Outputs**:
| Field | Description | Used For |
|-------|-------------|----------|
| `has_processing_errors` | Boolean for workflow branching | Error handling |
| `target_browser` | Browser name | Notifications |
| `target_hostname` | Endpoint hostname | Notifications |
| `resolved_username` | Resolved Windows username | Notifications |
| `detected_browser_profiles` | Array of profile names found | Notifications |
| `output_artifact_paths` | Array of expected output file paths | Collection stage |
| `execution_timestamp` | UTC timestamp | Artifact naming |
| `working_directory_path` | Working directory path | Collection stage |
| `exception_messages` | Error details if failed | Error handling |

**Notification Data Points**:
The following outputs are preserved for constructing analyst notifications:
- `target_hostname` - "Successfully started processing on **{hostname}**"
- `target_browser` - "Targeting **{browser}**"
- `detected_browser_profiles` - "Found **{count}** profiles: {profile_list}"
- `resolved_username` - "Collecting from user **{username}**"

---

### Stage 9: Processing Error Check

**Action Type**: Condition

Checks if the processing script completed successfully.

**Condition Logic**:
```
IF has_processing_errors == false
    → Continue to Stage 10
ELSE
    → Error handling path (notify analyst with exception_messages)
```

---

### Stage 10: Collection Script Execution (with Retry Loop)

**Action Type**: RTR - Run Script (with loop configuration)

Executes `hindsight_collection.ps1` on the target endpoint. Configured with retry logic to handle Hindsight processing time.

**Input Mapping**:
| Script Parameter | Source |
|------------------|--------|
| `expected_artifact_paths` | Stage 8 output |
| `working_directory_path` | Stage 4 variable |
| `target_hostname` | Stage 2 device details |
| `target_browser` | Stage 1 trigger input |
| `execution_timestamp` | Stage 8 output |

**Script Actions**:
1. Validate all expected artifact files exist
2. If missing → return error (triggers retry)
3. If complete → compress all artifacts to ZIP

**Retry Configuration**:
| Setting | Recommended Value |
|---------|-------------------|
| Max Retries | 10 |
| Retry Interval | 30 seconds |
| Retry Condition | `has_processing_errors == true` |

**Outputs**:
| Field | Description |
|-------|-------------|
| `has_processing_errors` | Triggers retry if artifacts not ready |
| `compressed_archive_path` | Path to ZIP for Get-File retrieval |
| `target_browser` | For notifications |
| `target_hostname` | For notifications |
| `execution_timestamp` | For notifications |
| `exception_messages` | Error details (triggers retry) |

---

### Stage 11: Get-File (Retrieve Archive)

**Action Type**: RTR - Get-File

Retrieves the compressed ZIP archive from the endpoint.

**Input Mapping**:
| Parameter | Source |
|-----------|--------|
| File Path | `compressed_archive_path` from Stage 10 |

**Outputs**:
- File available in Falcon console for analyst download

---

### Stage 12: Cleanup (Remove Working Directory)

**Action Type**: RTR - Run Command

Removes the working directory from the endpoint after successful retrieval.

**Command**:
```powershell
Remove-Item -Path "{working_directory_path}" -Recurse -Force
```

---

### Stage 13: Send Notification

**Action Type**: Notification (Email, Slack, Teams, etc.)

Notifies the analyst that collection is complete.

**Notification Template**:
```
Hindsight Collection Complete

Endpoint: {target_hostname}
Browser: {target_browser}
User: {resolved_username}
Profiles Collected: {detected_browser_profiles.count}
Timestamp: {execution_timestamp}

The forensic archive is ready for download in the Falcon console.
```

---

## Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          MANUAL TRIGGER                                     │
│  (falcon_sensor_id, target_browser, output_format, target_username)         │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       GET DEVICE DETAILS                                    │
│  Output: platform_name, hostname                                            │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
                                  ▼
                        ┌─────────────────┐
                        │  Windows?       │
                        └────────┬────────┘
                                 │
                    ┌────────────┴────────────┐
                    │                         │
                    ▼                         ▼
              ┌───────────┐            ┌─────────────┐
              │    Yes    │            │     No      │
              └─────┬─────┘            └──────┬──────┘
                    │                         │
                    ▼                         ▼
┌───────────────────────────────┐     ┌───────────────┐
│  CREATE VARIABLE              │     │  ABORT        │
│  working_directory_path       │     │  (Unsupported)│
└───────────────┬───────────────┘     └───────────────┘
                │
                ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  PREPARATION SCRIPT                                                       │
│  hindsight_preparation.ps1                                                │
└───────────────┬───────────────────────────────────────────────────────────┘
                │
                ▼
        ┌───────────────┐
        │  Errors?      │───Yes──▶ [Error Handling]
        └───────┬───────┘
                │ No
                ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  PUT-FILE                                                                 │
│  Deploy hindsight.exe to working directory                                │
└───────────────┬───────────────────────────────────────────────────────────┘
                │
                ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  PROCESSING SCRIPT                                                        │
│  hindsight_processing.ps1                                                 │
│  Outputs: profiles, artifact_paths, hostname, browser, timestamp          │
└───────────────┬───────────────────────────────────────────────────────────┘
                │
                ▼
        ┌───────────────┐
        │  Errors?      │───Yes──▶ [Error Handling]
        └───────┬───────┘
                │ No
                ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  COLLECTION SCRIPT (with retry loop)                                      │
│  hindsight_collection.ps1                                                 │
│  Validates artifacts exist, compresses to ZIP                             │
└───────────────┬───────────────────────────────────────────────────────────┘
                │
                ▼ (retry if files not ready)
        ┌───────────────┐
        │  Files Ready? │───No──▶ [Wait 30s, Retry]
        └───────┬───────┘
                │ Yes
                ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  GET-FILE                                                                 │
│  Retrieve ZIP archive from endpoint                                       │
└───────────────┬───────────────────────────────────────────────────────────┘
                │
                ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  CLEANUP                                                                  │
│  Remove working directory                                                 │
└───────────────┬───────────────────────────────────────────────────────────┘
                │
                ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  NOTIFICATION                                                             │
│  Alert analyst that collection is complete                                │
└───────────────────────────────────────────────────────────────────────────┘
```

## Error Handling Paths

### Preparation Failure
- Notify analyst with `exception_messages`
- Common causes: Permission denied, invalid path, disk full

### Processing Failure
- Notify analyst with `exception_messages`
- Common causes: User profile not found, browser not installed, no profiles detected

### Collection Retry Exhausted
- After max retries, notify analyst that artifacts never became ready
- Common causes: Hindsight crashed, antivirus interference, disk I/O issues

## Variable Flow Summary

| Variable | Created At | Used By |
|----------|------------|---------|
| `falcon_sensor_id` | Trigger | Get Device Details |
| `target_browser` | Trigger | Processing, Collection, Notification |
| `output_format` | Trigger | Processing |
| `target_username` | Trigger | Processing |
| `platform_name` | Device Details | Platform Condition |
| `hostname` | Device Details | Processing (as target_hostname), Notification |
| `working_directory_path` | Create Variable | Preparation, Put-File, Processing, Collection, Cleanup |
| `hindsight_executable_path` | Put-File | Processing |
| `output_artifact_paths` | Processing | Collection |
| `execution_timestamp` | Processing | Collection, Notification |
| `detected_browser_profiles` | Processing | Notification |
| `resolved_username` | Processing | Notification |
| `compressed_archive_path` | Collection | Get-File |
