# PC Pulse

A small Windows desktop app for finding resource-heavy processes and reviewing the apps you rarely use. Built with PowerShell and Windows Forms; no extra packages needed.

## Run

Download this repository as a ZIP, extract it, and double-click **Start-PCPulse.cmd**. Requires Windows 10 or 11 with Windows PowerShell 5.1 and an interactive desktop. Administrator access is not required. The launcher uses a process-local execution policy bypass to run the included script; it does not change your saved policy. Managed computers may block scripts.

## Features

- Live CPU and RAM rankings, refreshed every 2.5 seconds.
- Dark dashboard with CPU, process memory, and review summary cards.
- Group related processes by executable name.
- Search process names and sort by CPU, RAM, or name.
- Mark selected processes **Rarely use**, **Keep**, or **Unreviewed**.
- Filter rarely used processes and highlight ones above review thresholds.
- Preferences saved locally under `%LOCALAPPDATA%\PCPulse\preferences.json`.

CPU is the percentage of total logical CPU capacity consumed between samples. The first sample starts at zero. RAM is the sum of process working sets, which can count shared memory more than once; it is not total system RAM usage. Processes that exit or deny access are skipped. Processes are grouped by name, so separate applications with the same executable name share a label.

“Worth reviewing” means you marked a group **Rarely use** and it currently uses at least 1% CPU or 200 MB RAM. This is a simple review hint, not a judgment that the software is unnecessary. The app does not measure your historical app usage, stop processes, uninstall software, or change startup settings. Windows components and background services can be necessary even when you do not open them yourself.

All measurements and preferences stay on this computer. There is no telemetry or network access in the app. Only the source code belongs in GitHub; local preferences are stored outside the repository.

## Verify collection

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\PCPulse.ps1 -SmokeTest
```

The smoke test collects two real process snapshots and checks that CPU and memory values are valid. To test the UI, launch the app, change sort order, search a process, label it, and restart to confirm persistence.

Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\PCPulse.ps1 -SelfTest` to check table population and filtering. To render a preview with live local process data, use `-PreviewPath C:\full\path\preview.png`. Keep previews private if they show applications you do not want to share.

## Publish to GitHub

Create an empty repository named `pc-pulse` on GitHub. Open a terminal in this folder, then run:

```powershell
git remote add origin https://github.com/YOUR-USERNAME/pc-pulse.git
git push -u origin main
```

## Development

Edit `PCPulse.ps1`; the launcher always runs the current source. No build step is required.
