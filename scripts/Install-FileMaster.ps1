<#
.SYNOPSIS
    Installs the file-master agent for Claude Code.

.DESCRIPTION
    Copies agent\file-master.md to %USERPROFILE%\.claude\agents\ so you can
    ask Claude Code to "use file-master" from any session.

    Use -RegisterWindowsTask to also add a weekly Windows Task Scheduler job
    that runs the read-only scan without Claude (Sundays 7 PM). It is optional:
    the Claude desktop app's scheduled task is the usual routine.
#>
[CmdletBinding()]
param([switch]$RegisterWindowsTask)

$repo = Split-Path -Parent $PSScriptRoot
$agentsDir = Join-Path $env:USERPROFILE '.claude\agents'
New-Item -ItemType Directory -Force -Path $agentsDir | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'agent\file-master.md') -Destination (Join-Path $agentsDir 'file-master.md') -Force
Write-Host "Installed agent: $(Join-Path $agentsDir 'file-master.md')"

if ($RegisterWindowsTask) {
    $scan = Join-Path $repo 'scripts\Invoke-FileMasterScan.ps1'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scan`""
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 7pm
    Register-ScheduledTask -TaskName 'FileMaster Weekly Scan' -Action $action -Trigger $trigger -Description 'File Master read-only scan' -Force | Out-Null
    Write-Host "Registered Windows task 'FileMaster Weekly Scan' (Sundays 7 PM)."
}
