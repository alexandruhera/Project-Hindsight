# Hindsight Fusion SOAR

A browser forensics collection pipeline for CrowdStrike Falcon Fusion SOAR. Automates [Hindsight](https://github.com/obsidianforensics/hindsight) execution and artifact retrieval from Windows endpoints via Real Time Response (RTR).

## Overview

This project provides a three-phase workflow for collecting browser forensic data from remote Windows endpoints. Each phase is implemented as a standalone PowerShell script with JSON schema definitions for SOAR integration.

### Why Automate?

Manual Hindsight execution requires SSH/RDP access, command-line expertise, and file transfer coordination. This pipeline provides:

- **One-click initiation** - Trigger collection on one or many hosts from Falcon console
- **Automatic notification** - Get alerted when artifacts are ready for download
- **Automatic cleanup** - Working directories removed after retrieval
- **Forensic naming** - Consistent `{Hostname}-{Browser}-{Profile}-{Timestamp}` convention
- **Error handling** - Structured JSON output with exception tracking for workflow branching
- **Retry logic** - SOAR retry loops for artifact verification

## Supported Configurations

### Browsers
| Browser | Data Path |
|---------|-----------|
| Google Chrome | `AppData\Local\Google\Chrome\User Data` |
| Microsoft Edge | `AppData\Local\Microsoft\Edge\User Data` |
| Brave | `AppData\Local\BraveSoftware\Brave-Browser\User Data` |

### Output Formats
| Format | Description |
|--------|-------------|
| `xlsx` | Excel spreadsheet (default, analyst-friendly) |
| `sqlite` | SQLite database (for programmatic analysis) |
| `jsonl` | JSON Lines (for log ingestion/SIEM) |

### Username Resolution
- **Explicit**: Specify `target_username` to collect from a specific user profile
- **Auto-discovery**: Leave `target_username` empty to automatically detect the currently logged-in user via `Win32_ComputerSystem`

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Falcon Fusion SOAR                              │
├─────────────────────────────────────────────────────────────────────────┤
│  Trigger Input (falcon_sensor_id, target_browser, output_format, ...)  │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Phase 1: Preparation                                                   │
│  ─────────────────────                                                  │
│  • Remove existing working directory (clean slate)                      │
│  • Create fresh working directory                                       │
│  • Output: working_directory_path                                       │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Phase 2: Processing                                                    │
│  ────────────────────                                                   │
│  • Resolve target user (explicit or auto-discover)                      │
│  • Locate browser User Data directory                                   │
│  • Enumerate browser profiles (Default, Profile 1, Profile 2, ...)      │
│  • Launch Hindsight for each profile (fire-and-forget)                  │
│  • Output: output_artifact_paths[], execution_timestamp                 │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Phase 3: Collection (with retry loop)                                  │
│  ──────────────────────────────────────                                 │
│  • Validate all expected artifacts exist                                │
│  • If missing: return error → SOAR retry loop                           │
│  • If complete: compress to ZIP archive                                 │
│  • Output: compressed_archive_path                                      │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Falcon RTR Get-File → Analyst Notification                            │
└─────────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
hindsight-fusion-soar/
├── trigger-input.json                 # Workflow trigger schema
├── hindsight_preparation.ps1          # Phase 1: Directory setup
├── hindsight_preparation_input.json   # Phase 1 input schema
├── hindsight_preparation_output.json  # Phase 1 output schema
├── hindsight_processing.ps1           # Phase 2: Hindsight execution
├── hindsight_processing_input.json    # Phase 2 input schema
├── hindsight_processing_output.json   # Phase 2 output schema
├── hindsight_collection.ps1           # Phase 3: Artifact compression
├── hindsight_collection_input.json    # Phase 3 input schema
├── hindsight_collection_output.json   # Phase 3 output schema
├── WORKFLOW.md                        # Comprehensive SOAR workflow documentation
└── README.md
```

## Scripts

### Phase 1: hindsight_preparation.ps1

Prepares a clean working directory on the remote endpoint.

**Purpose**: Ensures no contamination from previous runs by removing and recreating the working directory.

**Input Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `working_directory_path` | string | Yes | Absolute path where artifacts will be stored |

**Output Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `has_processing_errors` | boolean | Workflow branching decision point |
| `working_directory_path` | string | Confirmed working directory path |
| `exception_messages` | string[] | Error details (only if errors occurred) |

---

### Phase 2: hindsight_processing.ps1

Executes Hindsight forensic analysis against browser profiles.

**Purpose**: Orchestrates four sequential sub-phases:
1. **User Profile Identification** - Resolves Windows user from explicit parameter or auto-discovers logged-in user
2. **Browser Data Path Resolution** - Locates browser's User Data directory
3. **Profile Detection** - Enumerates profiles matching `Default` or `Profile N` pattern
4. **Hindsight Execution** - Launches Hindsight in fire-and-forget mode for each profile

**Input Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `working_directory_path` | string | Yes | Output directory for artifacts |
| `hindsight_executable_path` | string | Yes | Path to hindsight.exe on endpoint |
| `output_format` | string | Yes | `xlsx`, `sqlite`, or `jsonl` |
| `target_browser` | string | Yes | `Google Chrome`, `Microsoft Edge`, or `Brave` |
| `target_hostname` | string | Yes | Endpoint hostname for artifact naming |
| `target_username` | string | No | Windows username (empty = auto-discover) |

**Output Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `has_processing_errors` | boolean | Workflow branching decision point |
| `target_browser` | string | Browser name (for notifications) |
| `target_hostname` | string | Endpoint hostname |
| `resolved_username` | string | Resolved Windows username |
| `detected_browser_profiles` | string[] | Found profile names |
| `output_artifact_paths` | string[] | Expected output file paths |
| `execution_timestamp` | string | UTC timestamp (yyyy-MM-ddTHH-mm) |
| `working_directory_path` | string | Working directory path |
| `exception_messages` | string[] | Error details (only if errors occurred) |

---

### Phase 3: hindsight_collection.ps1

Validates and compresses forensic artifacts for retrieval.

**Purpose**: Operates in two sub-phases:
1. **Artifact Validation** - Verifies all expected files exist (missing files trigger SOAR retry)
2. **Archive Compression** - Creates ZIP archive with consistent naming

**Input Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `expected_artifact_paths` | string[] | Yes | Paths to validate and compress |
| `working_directory_path` | string | Yes | Directory for ZIP output |
| `target_hostname` | string | Yes | For archive naming |
| `target_browser` | string | Yes | For archive naming |
| `execution_timestamp` | string | Yes | For archive naming |

**Output Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `has_processing_errors` | boolean | Triggers retry if artifacts missing |
| `compressed_archive_path` | string | Path to ZIP for Get-File retrieval |
| `target_browser` | string | Browser name (for notifications) |
| `target_hostname` | string | Endpoint hostname (for notifications) |
| `execution_timestamp` | string | Collection timestamp (for notifications) |
| `exception_messages` | string[] | Error details (triggers retry loop) |

---

### Workflow Trigger: trigger-input.json

Initial parameters provided when triggering the SOAR workflow.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `falcon_sensor_id` | string | Yes | - | CrowdStrike Agent ID (32-char hex) |
| `target_browser` | string | Yes | Google Chrome | Browser to collect |
| `output_format` | string | Yes | xlsx | Hindsight output format |
| `target_username` | string | No | - | Empty for auto-discovery |

## Output Naming Convention

Artifacts follow a consistent naming pattern:

```
{hostname}-{browser}-{profile}-{timestamp}.{format}
```

**Examples**:
- `WORKSTATION01-Google-Chrome-Default-2024-01-15T14-30.xlsx`
- `WORKSTATION01-Google-Chrome-Profile-1-2024-01-15T14-30.xlsx`
- `WORKSTATION01-Microsoft-Edge-Default-2024-01-15T14-30.sqlite`

**ZIP Archive**:
- `WORKSTATION01-Google-Chrome-2024-01-15T14-30.zip`

## Error Handling

All scripts guarantee JSON output regardless of errors. The `has_processing_errors` boolean enables workflow branching:

```
has_processing_errors = true  → Error path (notification, retry, or abort)
has_processing_errors = false → Success path (continue to next phase)
```

Errors are captured in the `exception_messages` array with descriptive messages:
- `"User profile not found: username"`
- `"Google Chrome data not found at: C:\Users\..."`
- `"No browser profiles found in: ..."`
- `"Artifact not ready: C:\hindsight\output.xlsx"`

## Prerequisites

### Platform
- Windows endpoints only (tested on Windows 10/11, Server 2016+)

### CrowdStrike RTR Permissions
- **Put-File**: Deploy hindsight.exe to endpoints
- **Run-Script**: Execute PowerShell scripts
- **Get-File**: Retrieve compressed artifacts

### Hindsight Binary
Download from [obsidianforensics/hindsight releases](https://github.com/obsidianforensics/hindsight/releases) and deploy to endpoints via RTR Put-File.

## Workflow Documentation

For comprehensive SOAR workflow documentation including:
- Stage-by-stage breakdown with action types
- Input/output mappings between stages
- Variable flow and dependencies
- Retry loop configuration
- Notification templates

See **[WORKFLOW.md](WORKFLOW.md)**

## Documentation

Full writeup with architecture diagrams and deployment guide:

**[Automating Hindsight Collection via CrowdStrike Fusion SOAR](https://alexandruhera.com/posts/automating-hindsight-collection-via-crowdstrike-fusion-soar/)**

## Author

[Alexandru Hera](https://alexandruhera.com)
