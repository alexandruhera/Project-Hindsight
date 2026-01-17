# Browser Forensics Collection Pipeline for CrowdStrike Falcon

A modular, on-demand collection pipeline built for CrowdStrike Falcon Fusion SOAR. This workflow leverages Real Time Response (RTR) to execute Hindsight on a remote Windows endpoint and collect forensic artifacts based on user-provided selections.

## Design Philosophy

This solution is implemented as a Fusion SOAR Workflow to provide orchestration and resilient error handling, replacing manual, repetitive RTR tasks.

### Timeout Prevention (Async Processing)
The primary value of this project is its ability to bypass RTR **script execution timeouts**. By employing an asynchronous "fire-and-forget" design, the processing script initiates Hindsight on the endpoint and exits immediately. This keeps the active RTR script execution time minimal, allowing the forensic tool to run for as long as necessary without being killed by the platform's timeout watchdog.

### Operational Agility
Instead of manually connecting to hosts, uploading tools, and waiting for results, analysts can trigger this workflow on-demand. The system handles the orchestration via a configurable polling loop, freeing the analyst to focus on other tasks until the notification arrives. Multiple executions can be initiated simultaneously across different hosts to speed up fleet-wide collection.

### Standardized Collection
Retrieval is handled via the **Get-File** action. Artifacts are automatically compressed and named according to a consistent convention (`Hostname-Browser-Profile-Timestamp`), ensuring forensic data integrity and ease of analysis.

## Key Capabilities

- Targeted Collection: Specific target_username provided by the user, or auto-discovery of the active user.
- On-Demand Execution: Analysts trigger the workflow manually and provide selections for browser and output format.
- Speed and Resilience: Decoupled design ensures collections succeed even on endpoints with extensive history.
- Multi-Browser Support: Supports Google Chrome, Microsoft Edge, and Brave.
- Flexible Formats: Export artifacts to .xlsx, .jsonl, or .sqlite.

---

## Architecture and Workflow

```text
MANAGEMENT PLANE (SOAR)                       ENDPOINT PLANE (Target System)
=======================                       ==============================

[ User Trigger ]
(Manual Selection)
       │
       ▼
[ Get Device Details ] ──(Non-Windows)──> [ Notify & Abort ]
       │
       ▼
[ Preparation Phase ] ──────────────────────> [ Clean Env & Create Dir ]
(hindsight_preparation.ps1)                           │
       │                                              ▼
       │ <─────(Error?)────────────────────── [ Notify & Abort ]
       │
       ▼
[ Deploy Tool ] ────────────────────────────> [ RTR Put-File: hindsight.exe ]
       │
       ▼
[ Processing Phase ] ───────────────────────> [ Resolve Target User ]
(hindsight_processing.ps1)                            │
       │                                              ▼
       │                                     [ Scan Browser Profiles ]
       │                                              │
       │                                              ▼
       │                                     [ ASYNC PROCESSING ]
       │                                     (Fire-and-Forget Process)
       │                                              │
       ▼                                              ▼
[ Polling Loop ]                              [ Generate Artifacts ]
(Configurable Wait)
       │
       ▼
[ Collection Phase ] ───────────────────────> [ Verify Artifacts Exist? ]
(hindsight_collection.ps1)                            │
       │                                     (Yes)    ▼
       │ <────────────────────────────────── [ Compress to .ZIP ]
       │
       │ <─────(Missing?)──────────────────── [ Retry Loop ]
       │
       ▼
[ Retrieval Phase ] <──────────────────────── [ RTR Get-File Action ]
       │
       ▼
[ Cleanup Phase ] ──────────────────────────> [ Remove Working Dir ]
       │
       ▼
[ Complete ]
```

---

## Project Structure

| Phase | Script | Input Schema | Output Schema |
| :--- | :--- | :--- | :--- |
| Preparation | hindsight_preparation.ps1 | hindsight_preparation_input.json | hindsight_preparation_output.json |
| Processing | hindsight_processing.ps1 | hindsight_processing_input.json | hindsight_processing_output.json |
| Collection | hindsight_collection.ps1 | hindsight_collection_input.json | hindsight_collection_output.json |

---

## Parameters and Inputs

### Trigger Inputs (trigger-input.json)
| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| deviceID | String (AID) | Yes | The Falcon Agent ID of the target host. |
| selected_browser | Enum | Yes | Google Chrome, Microsoft Edge, or Brave. |
| output_format | Enum | Yes | xlsx, sqlite, or jsonl. |
| target_username | String | No | Specific username to target. Defaults to auto-discovery. |

---

## Prerequisites

- Target Platform: Windows only (Validated via Workflow Get Device Details step).
- CrowdStrike Falcon RTR: Active session permissions with Put File, Get File, and Run Script capabilities.
- Hindsight Binary: Obtain `hindsight.exe` from the [Obsidian Forensics Releases](https://github.com/obsidianforensics/hindsight/releases).

### Required Roles
- Workflow Author: Workflow Author & Real-Time Response Administrator.
- Workflow Executor: Workflow Executor.

---

## Acknowledgements

- Author: [Alexandru Hera](https://alexandruhera.com)
- Tooling: [Hindsight Project](https://github.com/obsidianforensics/hindsight) by Obsidian Forensics.
- Platform: CrowdStrike Falcon Fusion SOAR.
