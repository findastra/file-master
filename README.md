# File Master

Keeps a Windows PC organized. It regularly audits your folders and projects,
points out what's broken or wasteful, and gives you a plan of renames and moves
to approve. **It never deletes anything.**

It has three parts:

| Part | What it is | When it runs |
|---|---|---|
| **Scanner** (`scripts/Invoke-FileMasterScan.ps1`) | A read-only PowerShell audit | Whenever you run it, or on a schedule |
| **`file-master` agent** (`agent/file-master.md`) | A Claude Code subagent that runs the scanner, adds judgment, and walks you through fixes | When you ask Claude to "use file-master" |
| **Weekly routine** | A Claude desktop scheduled task that runs the agent's checklist and sends you a summary | Every Sunday evening while the Claude app is open |

## What it checks

- **Duplicates.** Large files stored more than once, found by size plus a partial hash and re-checked with a full SHA-256 before anything moves.
- **Partial downloads** (`.opdownload`, `.crdownload`, `.part`)
- **Files with no extension.** It detects the real type (PNG, JPG, PDF, MP4, ZIP, and more) from the file's first bytes.
- **Doubled extensions** like `fix.bat.bat`, which is the hidden-extensions trap.
- **Piles** of installers and `.log` files
- **Empty folders**
- **Sensitive-looking files** (keys, passwords) sitting at a drive root, on the Desktop, or in Documents. Only the name is checked; File Master never opens them.
- **Git repo health.** It flags repos with no commits, no GitHub remote, unpushed or uncommitted work, no `.gitignore`, nested repos, folder/repo name mismatches, and big files about to be committed.
- **Project health,** with extra attention on **emerging projects** (created in the last 21 days). It checks the name, git, README, and whether the folder holds only assets and no code.
- **Stale projects** with no changes in 60 days

## Quick start

```powershell
# 1. Scan (read-only). Opens the report when done.
.\run-scan.cmd

# 2. Review reports\<run-id>\plan.csv and put "yes" in the Approved column for rows you want.

# 3. Dry run, then apply
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-FileMasterPlan.ps1 -PlanPath .\reports\<run-id>\plan.csv
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-FileMasterPlan.ps1 -PlanPath .\reports\<run-id>\plan.csv -Apply

# Changed your mind?
powershell -ExecutionPolicy Bypass -File .\scripts\Undo-FileMasterPlan.ps1 -UndoLog .\reports\<run-id>\undo-<time>.jsonl
```

Why `-ExecutionPolicy Bypass`? Windows blocks `.ps1` scripts by default. Bypass
allows just this one run without changing the setting for the whole PC.

### What's a dry run?

A rehearsal. The plan script prints exactly what it *would* move or rename, then stops
without changing anything. Always dry-run first. It catches surprises, like a rename whose
target name already exists, while undoing still costs nothing. Add `-Apply` only once
the dry-run output looks right.

### Plan actions

| Action | What happens |
|---|---|
| `Rename` / `Move` | Item moves to `Destination`. It is skipped if something already exists there. |
| `Quarantine` | Item moves to `<drive>\_file-master-holding\<run-id>\...`, keeping its original folder layout. You empty that folder yourself. |
| `RemoveEmpty` | Folder is removed only if it is still empty |
| `Review` | Report only. Decide by hand or ask the agent. |

## Install the agent

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-FileMaster.ps1
```

This copies the agent to `%USERPROFILE%\.claude\agents\file-master.md`. In any Claude Code
session you can then say *"use file-master to check my projects"*.

Add `-RegisterWindowsTask` for a weekly scan through Windows Task Scheduler that runs without Claude.

## Configuration

`config/file-master.config.json` holds generic defaults. Copy it to
`config/file-master.config.local.json` (git-ignored) and add your own drives and folders.
The local file takes priority.

| Key | Meaning |
|---|---|
| `roots` | Folders to scan |
| `projectRoots` | Where your projects live (each child folder counts as a project) |
| `driveRoots` | Places checked for exposed sensitive files |
| `skipDirs` / `skipPaths` | Folder names or full paths to ignore |
| `preferKeepUnder` | When duplicates exist, keep the copy under these folders (e.g. your archive drive) |
| `duplicateMinMB`, `largeFileMB`, `repoLargeFileMB` | Size thresholds |
| `emergingProjectDays`, `staleProjectDays` | Project age thresholds |

## Privacy

Reports contain your file paths, so `reports/` is git-ignored. The scanner only reads
file names, sizes, dates, the first 16 bytes (for type detection), and hashes. It does
not read document contents.


## File Master web app

*A pet app by Astra.*

Open [file-master-20261008.html](file-master-20261008.html) in a modern browser, or double-click File Master in Astra's Pet Apps. The nine original pet moods and manifest are included.

Limits: this web app does not install or start Windows programs. Where an existing web app is available, the Cage opens that app. Draft controls store their data in the current browser and do not imply connected services. Existing application instructions above still apply.

Version [v0.1.1-20261008-pets](https://github.com/findastra/file-master/tree/v0.1.1-20261008-pets). Added with OpenAI Codex (GPT-6), 2026-10-08.
