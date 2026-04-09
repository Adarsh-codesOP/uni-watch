# VTU Auto-Progress Bypasser

A beautiful, fast, API-driven CLI tool to automate video progress completion on the VTU portal.

## Features
- **API-Driven**: Completes hours of video in seconds by safely pinging the backend.
- **Parallel Processing**: Runs up to 3 lectures simultaneously for maximum speed.
- **Smart Skip**: Automatically skips lectures already marked complete — no wasted API calls.
- **Network Recovery**: Detects connection drops, waits for reconnection, and resumes right where it left off.
- **Retry Failed**: Offers to retry any lectures that failed at the end of the run.
- **Course Selection**: Choose to auto-run all courses or pick specific ones from a menu.
- **Summary Dashboard**: End-of-run report with total, skipped, completed, failed, and elapsed time.
- **Beautiful UI**: Built with `rich` — gradient logo, styled tables, progress bars, and phase indicators.
- **Secure**: Password input is hidden. No credentials are saved to disk.

## Installation

To install the tool **globally** so it is automatically added to your system's `PATH` and accessible from any folder, we recommend using `uv` or `pipx`:

```bash
# Recommended: Install using uv
uv tool install vtu-auto

# Alternative: Install using pipx
pipx install vtu-auto
```

*(You can also use standard `pip install vtu-auto`, but ensuring your environment variables are configured correctly is easier with `uv`/`pipx`).*

## Usage

Simply run from any terminal:
```bash
vtu-auto
```

To view underlying API HTTP response trace logs locally:
```bash
vtu-auto --log
```

---
<div align="center">
  <sub><b>Terms & Conditions:</b> This software is provided strictly for educational purposes and concept demonstration. The authors do not condone or support Terms of Service violations. By using this tool, the user accepts full responsibility for their actions. The authors bear zero legal obligation or liability for any consequences (academic penalties, suspensions, etc.) resulting from the use of this software.</sub>
</div>
