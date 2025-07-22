# Tools Directory

This directory contains utility scripts and helper tools for the LogRhythm Archive Retention Manager project.

## Contents

### winrm_helper.py
Python utility for remote Windows PowerShell execution via WinRM. Provides convenient commands for:
- Testing NAS connectivity
- Running retention scripts remotely
- Managing credentials
- Executing dry-run and production operations

Usage:
```bash
source winrm_env/bin/activate
python3 tools/winrm_helper.py [command]
```

Available commands:
- `local` - Test with local path
- `nas` - Test NAS credentials
- `nas_dry_run [days]` - Dry-run with custom retention
- `nas_execute [days]` - Execute with custom retention
- `parameters` - Test various parameter combinations

## Note
These tools are auxiliary utilities and not part of the core retention management functionality.