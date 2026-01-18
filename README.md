# Hindsight Fusion SOAR

A browser forensics collection pipeline for CrowdStrike Falcon Fusion SOAR. Automates [Hindsight](https://github.com/obsidianforensics/hindsight) execution and artifact retrieval from Windows endpoints via Real Time Response (RTR).

For a deep dive into the architecture, design decisions, and workflow logic, please read the full article:
**[Automating Hindsight Collection via CrowdStrike Fusion SOAR](https://alexandruhera.com/posts/automating-hindsight-collection-via-crowdstrike-fusion-soar/)**

## Overview

This project provides a "fire-and-forget" workflow for collecting browser forensic data. It solves the problem of manual RTR collection by orchestrating the entire lifecycle: preparation, execution, and retrieval.

### Key Features

- **One-click initiation**: Trigger collection on one or many hosts.
- **Auto-discovery**: Automatically identifies active users and browser profiles.
- **Resilient**: Uses SOAR retry loops to handle long-running forensic jobs.
- **Clean**: Automatically cleans up working directories after retrieval.

## Project Structure

```
hindsight-fusion-soar/
├── trigger-input.json                 # Workflow trigger schema
├── hindsight_preparation.ps1          # Phase 1: Directory setup
├── hindsight_processing.ps1           # Phase 2: Hindsight execution
├── hindsight_collection.ps1           # Phase 3: Artifact compression
├── *_input.json / *_output.json       # Schema definitions for SOAR integration
└── README.md
```

## Quick Start

### Prerequisites
1.  **Hindsight Binary**: Download `hindsight.exe` from [Obsidian Forensics](https://github.com/obsidianforensics/hindsight/releases).
2.  **CrowdStrike RTR**: Ensure you have `Put-File`, `Run-Script`, and `Get-File` permissions.

### Deployment
1.  **Upload Binary**: Add `hindsight.exe` to your RTR "Put Files" library.
2.  **Create Scripts**: Upload the three `.ps1` files as RTR Response Scripts.
3.  **Build Workflow**: Create a Fusion SOAR workflow using the schema definitions provided in the `*_input.json` and `*_output.json` files.

## Workflow Inputs

| Parameter | Description |
|-----------|-------------|
| `falcon_sensor_id` | Agent ID of the target endpoint. |
| `target_browser` | `Google Chrome`, `Microsoft Edge`, or `Brave`. |
| `output_format` | `xlsx`, `sqlite`, or `jsonl`. |
| `target_username` | Optional. Leave empty to auto-discover the active user. |

## Author

[Alexandru Hera](https://alexandruhera.com)