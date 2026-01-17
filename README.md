# Hindsight Fusion SOAR

A browser forensics collection pipeline for CrowdStrike Falcon Fusion SOAR. Automates [Hindsight](https://github.com/obsidianforensics/hindsight) execution and artifact retrieval from Windows endpoints via RTR.

## The Problem

RTR script execution has a hard timeout. Long-running forensic tools like Hindsight get killed before completion.

## The Solution

**Fire-and-forget execution** with polling-based collection:

```powershell
# Instead of blocking...
Start-Process -FilePath "hindsight.exe" -Wait  # Will timeout

# Start and exit immediately
Start-Process -FilePath "hindsight.exe" -NoNewWindow  # Returns instantly
```

The workflow polls for artifacts in a retry loop, decoupling execution from verification.

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SOAR WORKFLOW                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                  │
│  │   TRIGGER    │───▶│  VALIDATE    │───▶│   PREPARE    │                  │
│  │  (Manual)    │    │  (Windows?)  │    │  (Clean Dir) │                  │
│  └──────────────┘    └──────────────┘    └──────────────┘                  │
│                                                 │                           │
│                                                 ▼                           │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                  │
│  │   CLEANUP    │◀───│   COLLECT    │◀─┬─│   PROCESS    │──▶ Hindsight     │
│  │ (Remove Dir) │    │ (ZIP & Get)  │  │ │ (Async Start)│    (runs async)  │
│  └──────────────┘    └──────────────┘  │ └──────────────┘                  │
│         │                   │          │                                    │
│         │            ┌──────┴──────┐   │                                    │
│         │            │ Files Ready? │──┘                                    │
│         │            │   (Poll)    │ No ──▶ Wait ──▶ Retry                  │
│         │            └─────────────┘                                        │
│         ▼                                                                   │
│  ┌──────────────┐                                                           │
│  │   COMPLETE   │                                                           │
│  │  (Notify)    │                                                           │
│  └──────────────┘                                                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Features

- **Async execution** - Bypasses RTR timeouts via fire-and-forget pattern
- **Multi-browser support** - Google Chrome, Microsoft Edge, Brave
- **Flexible output** - xlsx, sqlite, or jsonl formats
- **Targeted collection** - Specify username or auto-discover active user
- **Standardized naming** - `Hostname-Browser-Profile-Timestamp` convention

## Project Structure

| Phase | Script | Purpose |
|-------|--------|---------|
| Preparation | `hindsight_preparation.ps1` | Clean and create working directory |
| Processing | `hindsight_processing.ps1` | Launch Hindsight async, record expected paths |
| Collection | `hindsight_collection.ps1` | Verify artifacts exist, compress to ZIP |

Each script has corresponding `_input.json` and `_output.json` schemas.

## Workflow Inputs

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `deviceID` | String | Yes | Falcon Agent ID |
| `selected_browser` | Enum | Yes | Google Chrome, Microsoft Edge, or Brave |
| `output_format` | Enum | Yes | xlsx, sqlite, or jsonl |
| `target_username` | String | No | Specific user (defaults to active user) |

## Prerequisites

- **Platform**: Windows endpoints only
- **RTR Permissions**: Put-File, Get-File, Run-Script
- **Binary**: Download `hindsight.exe` from [Obsidian Forensics releases](https://github.com/obsidianforensics/hindsight/releases)

### Required Roles

| Role | Permissions |
|------|-------------|
| Workflow Author | Workflow Author, Real-Time Response Administrator |
| Workflow Executor | Workflow Executor |

## Deployment

1. Upload `hindsight.exe` to RTR Put-Files
2. Create RTR scripts from the PowerShell files
3. Build the Fusion SOAR workflow using the architecture above
4. Configure polling loop interval and max retries

## Acknowledgements

- [Hindsight](https://github.com/obsidianforensics/hindsight) by Obsidian Forensics
- CrowdStrike Falcon Fusion SOAR

## Author

[Alexandru Hera](https://alexandruhera.com)
