# Hindsight Fusion SOAR

Automates [Hindsight](https://github.com/obsidianforensics/hindsight) browser forensics collection via CrowdStrike Falcon Fusion SOAR.

**Full documentation**: [Automating Hindsight Collection via CrowdStrike Fusion SOAR](https://alexandruhera.com/posts/automating-hindsight-collection-via-crowdstrike-fusion-soar/)

## Overview

A "fire-and-forget" workflow that orchestrates browser artifact collection from Windows endpoints via RTR. Supports Chrome, Edge, and Brave with automatic user and profile discovery.

## Requirements

| Falcon Role | Purpose |
|:------------|:--------|
| RTR Administrator | Manage RTR scripts |
| Workflow Author | Create SOAR workflows |
| Workflow Executor | Run workflows on-demand |

## Quick Start

1. Upload `hindsight.exe` from [Hindsight releases](https://github.com/obsidianforensics/hindsight/releases) to RTR Put-Files
2. Create RTR scripts from the `.ps1` files with their corresponding `*_input.json` and `*_output.json` schemas
3. Enable **Share with Workflows** on each script
4. Build the Fusion SOAR workflow per the [blog post](https://alexandruhera.com/posts/automating-hindsight-collection-via-crowdstrike-fusion-soar/)

## Workflow Inputs

| Parameter | Description |
|:----------|:------------|
| `falcon_sensor_id` | Target endpoint Agent ID |
| `target_browser` | `Google Chrome`, `Microsoft Edge`, or `Brave` |
| `output_format` | `xlsx`, `sqlite`, or `jsonl` |
| `target_username` | Optional - auto-discovers active user if empty |

## Author

[Alexandru Hera](https://alexandruhera.com)