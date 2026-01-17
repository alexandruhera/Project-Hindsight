# Project Hindsight

A browser forensics collection pipeline for CrowdStrike Falcon Fusion SOAR. Automates [Hindsight](https://github.com/obsidianforensics/hindsight) execution and artifact retrieval from Windows endpoints via RTR.

## Why?

An analyst could run these commands manually. The value is in the orchestration:

- **One-click initiation** - Trigger collection on one or many hosts
- **Automatic notification** - Get alerted when artifacts are ready
- **Automatic cleanup** - Working directories removed after retrieval
- **Forensic naming** - Consistent `Hostname-Browser-Profile-Timestamp` convention

## Features

- **Multi-browser** - Google Chrome, Microsoft Edge, Brave
- **Flexible output** - xlsx, sqlite, or jsonl
- **Targeted collection** - Specify username or auto-discover active user

## Project Structure

| Phase | Script | Purpose |
|-------|--------|---------|
| Preparation | `hindsight_preparation.ps1` | Clean and create working directory |
| Processing | `hindsight_processing.ps1` | Launch Hindsight, record expected paths |
| Collection | `hindsight_collection.ps1` | Verify artifacts, compress to ZIP |

Each script has corresponding `_input.json` and `_output.json` schemas.

## Prerequisites

- **Platform**: Windows endpoints only
- **RTR Permissions**: Put-File, Get-File, Run-Script
- **Binary**: [hindsight.exe](https://github.com/obsidianforensics/hindsight/releases)

## Documentation

See the full writeup with architecture diagrams and deployment guide:

**[Automating Hindsight Collection via CrowdStrike Fusion SOAR](https://alexandruhera.com/posts/automating-hindsight-collection-via-crowdstrike-fusion-soar/)**

## Author

[Alexandru Hera](https://alexandruhera.com)
