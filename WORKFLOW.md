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

### Stage 4: Create Workflow Variables

**Action Type**: Falcon SOAR - Create Variable (x2)

Creates workflow variables for paths. This approach keeps paths configurable without modifying scripts.

**Variables Created**:
| Variable Name | Value | Purpose |
|---------------|-------|---------|
| `working_directory_path` | `C:\hindsight` (or configured path) | Working directory for artifacts |
| `compressed_archive_path` | (empty - populated by collection loop) | Output ZIP path for loop output |

**Design Decision**: Using SOAR variables rather than hardcoding in scripts allows:
- Easy path changes without script modifications
- Environment-specific configurations
- Audit trail of configuration changes
- Loop output variable population

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
| Target Path | `{working_directory_path}` |
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
| `output_artifact_paths` | Array of expected output file paths | Collection loop |
| `execution_timestamp` | UTC timestamp | Artifact naming |
| `working_directory_path` | Working directory path | Collection loop |
| `exception_messages` | Error details if failed | Error handling |

**Notification Data Points** (preserved for final notification):
- `target_hostname` - Endpoint where collection ran
- `target_browser` - Browser that was targeted
- `detected_browser_profiles` - Profiles found and collected
- `resolved_username` - User whose data was collected

---

### Stage 9: Processing Error Check

**Action Type**: Condition

Checks if the processing script completed successfully.

**Condition Logic**:
```
IF has_processing_errors == false
    → Continue to Stage 10 (Collection Loop)
ELSE
    → Error handling path (notify analyst with exception_messages)
```

---

### Stage 10: Collection Loop

**Action Type**: Loop

A loop structure that repeatedly checks for artifact completion and compresses when ready.

**Loop Structure**:
```
┌─────────────────────────────────────────────────────────────────┐
│  LOOP START                                                     │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  10a: Collection Script                                   │  │
│  │  hindsight_collection.ps1                                 │  │
│  │  - Validates all output_artifact_paths exist              │  │
│  │  - If complete: creates ZIP archive                       │  │
│  │  - Outputs: has_processing_errors, compressed_archive_path│  │
│  └─────────────────────────┬─────────────────────────────────┘  │
│                            │                                    │
│                            ▼                                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  10b: Condition - Files Ready?                            │  │
│  │  IF has_processing_errors == true                         │  │
│  │      → Continue to 10c (Sleep)                            │  │
│  │  ELSE                                                     │  │
│  │      → Continue to 10d (Break)                            │  │
│  └─────────────────────────┬─────────────────────────────────┘  │
│                            │                                    │
│            ┌───────────────┴───────────────┐                    │
│            │                               │                    │
│            ▼                               ▼                    │
│  ┌─────────────────────┐       ┌─────────────────────────────┐  │
│  │  10c: Sleep Action  │       │  10d: Break Action          │  │
│  │  Wait 1 minute      │       │  Exit loop                  │  │
│  │  (configurable)     │       │  Output: compressed_archive │  │
│  │  → Loop back to 10a │       │  _path                      │  │
│  └─────────────────────┘       └─────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Stage 10a: Collection Script

**Action Type**: RTR - Run Script

**Input Mapping**:
| Script Parameter | Source |
|------------------|--------|
| `expected_artifact_paths` | Stage 8 `output_artifact_paths` |
| `working_directory_path` | Stage 4 variable |
| `target_hostname` | Stage 2 device details |
| `target_browser` | Stage 1 trigger input |
| `execution_timestamp` | Stage 8 output |

**Script Actions**:
1. Validate all expected artifact files exist
2. If any missing → set `has_processing_errors = true`
3. If all present → compress to ZIP, set `has_processing_errors = false`

**Outputs**:
| Field | Description |
|-------|-------------|
| `has_processing_errors` | `true` if artifacts not ready, `false` if ZIP created |
| `compressed_archive_path` | Path to created ZIP (only valid when `has_processing_errors = false`) |
| `exception_messages` | Details on which files are missing |

#### Stage 10b: Files Ready Condition

**Action Type**: Condition

**Condition Logic**:
```
IF has_processing_errors == true
    → Artifacts not ready, go to Sleep (10c)
ELSE
    → ZIP created successfully, go to Break (10d)
```

#### Stage 10c: Sleep Action

**Action Type**: Falcon SOAR - Sleep

Pauses execution before retrying artifact check.

| Setting | Value |
|---------|-------|
| Duration | 1 minute (configurable by workflow author) |

After sleep, loop returns to Stage 10a to re-run collection script.

#### Stage 10d: Break Action

**Action Type**: Loop - Break

Exits the loop when artifacts are ready and ZIP is created.

**Output Variable**:
| Variable | Value | Purpose |
|----------|-------|---------|
| `compressed_archive_path` | Path from collection script | Passed to Get-File stage |

---

### Stage 11: Get-File (Retrieve Archive)

**Action Type**: RTR - Get-File

Retrieves the compressed ZIP archive from the endpoint.

**Input Mapping**:
| Parameter | Source |
|-----------|--------|
| File Path | `compressed_archive_path` from Stage 10 loop output |

**Outputs**:
- File available in Falcon console for analyst download
- Success/failure status for parallel stage trigger

---

### Stage 12: Parallel Execution (Cleanup + Notification)

**Action Type**: Parallel

After successful Get-File, two actions execute simultaneously.

```
┌─────────────────────────────────────────────────────────────────┐
│  PARALLEL EXECUTION                                             │
│                                                                 │
│  ┌─────────────────────────┐   ┌─────────────────────────────┐  │
│  │  12a: Cleanup           │   │  12b: Send Notification     │  │
│  │  Remove working dir     │   │  Alert analyst              │  │
│  └─────────────────────────┘   └─────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Stage 12a: Cleanup (Remove Working Directory)

**Action Type**: RTR - Run Command

Removes the working directory from the endpoint after successful retrieval.

**Command**:
```powershell
Remove-Item -Path "{working_directory_path}" -Recurse -Force
```

#### Stage 12b: Send Notification

**Action Type**: Notification (Email, Slack, Teams, etc.)

Notifies the analyst that collection is complete.

**Notification Template** (using actual variable names):
```
Hindsight Collection Complete

Endpoint: ${target_hostname}
Browser: ${target_browser}
User: ${resolved_username}
Profiles Collected: ${detected_browser_profiles}
Timestamp: ${execution_timestamp}
Archive: ${compressed_archive_path}

The forensic archive is ready for download in the Falcon console.
```

**Variable Reference**:
| Template Variable | Source Stage | Schema Field |
|-------------------|--------------|--------------|
| `${target_hostname}` | Stage 8 | `target_hostname` |
| `${target_browser}` | Stage 8 | `target_browser` |
| `${resolved_username}` | Stage 8 | `resolved_username` |
| `${detected_browser_profiles}` | Stage 8 | `detected_browser_profiles` |
| `${execution_timestamp}` | Stage 8 | `execution_timestamp` |
| `${compressed_archive_path}` | Stage 10 | `compressed_archive_path` |

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
                        │   Windows?      │
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
│  CREATE VARIABLES             │     │  ABORT        │
│  • working_directory_path     │     │  (Unsupported)│
│  • compressed_archive_path    │     └───────────────┘
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  PREPARATION SCRIPT                                                       │
│  hindsight_preparation.ps1                                                │
└───────────────┬───────────────────────────────────────────────────────────┘
                │
                ▼
        ┌───────────────┐
        │  Errors?      │───Yes──▶ [Error Notification]
        └───────┬───────┘
                │ No
                ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  PUT-FILE                                                                 │
│  Deploy hindsight.exe to working_directory_path                           │
└───────────────┬───────────────────────────────────────────────────────────┘
                │
                ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  PROCESSING SCRIPT                                                        │
│  hindsight_processing.ps1                                                 │
│  Outputs: detected_browser_profiles, output_artifact_paths,               │
│           target_hostname, target_browser, resolved_username,             │
│           execution_timestamp                                             │
└───────────────┬───────────────────────────────────────────────────────────┘
                │
                ▼
        ┌───────────────┐
        │  Errors?      │───Yes──▶ [Error Notification]
        └───────┬───────┘
                │ No
                ▼
┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐
│  COLLECTION LOOP                                                          │
│ ┌───────────────────────────────────────────────────────────────────────┐ │
│ │  COLLECTION SCRIPT                                                    │ │
│ │  hindsight_collection.ps1                                             │ │
│ │  Validates output_artifact_paths exist, creates ZIP                   │ │
│ └───────────────────────────────────────────────────────────────────────┘ │
│                               │                                           │
│                               ▼                                           │
│                     ┌─────────────────┐                                   │
│                     │ has_processing  │                                   │
│                     │ _errors?        │                                   │
│                     └────────┬────────┘                                   │
│                              │                                            │
│              ┌───────────────┴───────────────┐                            │
│              │                               │                            │
│              ▼                               ▼                            │
│     ┌─────────────────┐           ┌─────────────────┐                     │
│     │  true (waiting) │           │  false (ready)  │                     │
│     └────────┬────────┘           └────────┬────────┘                     │
│              │                             │                              │
│              ▼                             ▼                              │
│     ┌─────────────────┐           ┌─────────────────┐                     │
│     │  SLEEP          │           │  BREAK          │                     │
│     │  1 minute       │           │  Output:        │                     │
│     └────────┬────────┘           │  compressed_    │                     │
│              │                    │  archive_path   │                     │
│              └──────┐             └────────┬────────┘                     │
│                     │                      │                              │
│                     ▼                      │                              │
│              [Loop back]                   │                              │
└ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┼ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘
                                             │
                                             ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  GET-FILE                                                                 │
│  Retrieve compressed_archive_path from endpoint                           │
└───────────────────────────────────────────────────────────────────────────┘
                                             │
                                             ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  PARALLEL EXECUTION                                                       │
│  ┌─────────────────────────────┐   ┌─────────────────────────────────┐   │
│  │  CLEANUP                    │   │  NOTIFICATION                   │   │
│  │  Remove-Item                │   │  • ${target_hostname}           │   │
│  │  working_directory_path     │   │  • ${target_browser}            │   │
│  │                             │   │  • ${resolved_username}         │   │
│  │                             │   │  • ${detected_browser_profiles} │   │
│  │                             │   │  • ${execution_timestamp}       │   │
│  └─────────────────────────────┘   └─────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────────────┘
```

## Error Handling Paths

### Preparation Failure
- Notify analyst with `exception_messages`
- Common causes: Permission denied, invalid path, disk full

### Processing Failure
- Notify analyst with `exception_messages`
- Common causes: User profile not found, browser not installed, no profiles detected

### Collection Loop Timeout
- If loop runs indefinitely, configure max iterations in SOAR
- Notify analyst that artifacts never became ready
- Common causes: Hindsight crashed, antivirus interference, disk I/O issues

## Variable Flow Summary

| Variable | Created At | Used By |
|----------|------------|---------|
| `falcon_sensor_id` | Trigger | Get Device Details |
| `target_browser` | Trigger | Processing, Collection, Notification |
| `output_format` | Trigger | Processing |
| `target_username` | Trigger | Processing |
| `platform_name` | Device Details | Platform Condition |
| `hostname` | Device Details | Processing (as `target_hostname`) |
| `working_directory_path` | Create Variable | Preparation, Put-File, Processing, Collection, Cleanup |
| `compressed_archive_path` | Create Variable / Collection | Loop Output, Get-File, Notification |
| `hindsight_executable_path` | Put-File | Processing |
| `output_artifact_paths` | Processing | Collection Loop |
| `execution_timestamp` | Processing | Collection, Notification |
| `detected_browser_profiles` | Processing | Notification |
| `resolved_username` | Processing | Notification |
| `target_hostname` | Processing | Collection, Notification |
