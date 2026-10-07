<#
.SYNOPSIS
    Reverses changes recorded in a File Master undo log.

.EXAMPLE
    .\scripts\Undo-FileMasterPlan.ps1 -UndoLog .\reports\2026-10-06_2300\undo-20261006-231500.jsonl
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UndoLog,
    [switch]$WhatIf
)

$entries = @(Get-Content -LiteralPath $UndoLog | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
[array]::Reverse($entries)
$ok = 0; $bad = 0
foreach ($e in $entries) {
    if ($e.Action -eq 'RemoveEmpty') {
        if (-not $WhatIf) { New-Item -ItemType Directory -Force -Path $e.From | Out-Null }
        Write-Host "recreate folder $($e.From)"; $ok++; continue
    }
    if (-not (Test-Path -LiteralPath $e.To)) { Write-Host "SKIP (not found): $($e.To)"; $bad++; continue }
    if (Test-Path -LiteralPath $e.From) { Write-Host "SKIP (original path occupied): $($e.From)"; $bad++; continue }
    if (-not $WhatIf) {
        $parent = Split-Path -Parent $e.From
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        Move-Item -LiteralPath $e.To -Destination $e.From
    }
    Write-Host "restore $($e.To) -> $($e.From)"; $ok++
}
Write-Host "Undo complete: $ok restored, $bad skipped."
