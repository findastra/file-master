<#
.SYNOPSIS
    Carries out the approved rows of a File Master plan.csv.

.DESCRIPTION
    Dry run by default: prints what would happen. Add -Apply to do it.

    Only rows whose Approved column is yes/y/x/1/true are touched (or the
    rows you list with -Ids). Supported actions:
      Move / Rename  move the item to Destination
      Quarantine     move the item into <drive>\_file-master-holding\<run>\
                     (duplicates are re-checked with a full SHA256 first)
      RemoveEmpty    remove a folder only if it is still empty

    Nothing is ever deleted. Every change is written to an undo log next to
    the plan; Undo-FileMasterPlan.ps1 reverses it.

.EXAMPLE
    .\scripts\Invoke-FileMasterPlan.ps1 -PlanPath .\reports\2026-10-06_2300\plan.csv
.EXAMPLE
    .\scripts\Invoke-FileMasterPlan.ps1 -PlanPath .\reports\2026-10-06_2300\plan.csv -Apply
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [switch]$Apply,
    [int[]]$Ids
)

. (Join-Path $PSScriptRoot 'lib\FileMaster.Common.ps1')

$rows = @(Import-Csv -LiteralPath $PlanPath)
$selected = @(if ($Ids) { $rows | Where-Object { $Ids -contains [int]$_.Id } } else { $rows | Where-Object { $_.Approved -match '^\s*(y|yes|x|1|true)\s*$' } })
if (-not $selected.Count) { Write-Host "No approved rows. Put 'yes' in the Approved column of $PlanPath (or pass -Ids)."; return }

$undoPath = Join-Path (Split-Path -Parent $PlanPath) ("undo-{0}.jsonl" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$mode = if ($Apply) { 'APPLY' } else { 'DRY RUN' }
Write-Host "$mode - $($selected.Count) row(s)"
$done = 0; $skipped = 0

foreach ($r in $selected) {
    $src = $r.Source; $dst = $r.Destination
    $tag = "[$($r.Id)] $($r.Action)"
    if (-not (Test-Path -LiteralPath $src)) { Write-Host "$tag SKIP (source gone): $src"; $skipped++; continue }

    if ($r.Action -eq 'RemoveEmpty') {
        if (Get-ChildItem -LiteralPath $src -Force -ErrorAction SilentlyContinue | Select-Object -First 1) { Write-Host "$tag SKIP (no longer empty): $src"; $skipped++; continue }
        if ($Apply) {
            Remove-Item -LiteralPath $src -Force
            (@{ Action = 'RemoveEmpty'; From = $src } | ConvertTo-Json -Compress) | Add-Content -LiteralPath $undoPath -Encoding UTF8
        }
        Write-Host "$tag $src"; $done++; continue
    }

    if ($r.Action -notin @('Move', 'Rename', 'Quarantine')) { Write-Host "$tag SKIP (not an automatic action)"; $skipped++; continue }
    if (-not $dst) { Write-Host "$tag SKIP (no destination)"; $skipped++; continue }
    if (Test-Path -LiteralPath $dst) { Write-Host "$tag SKIP (destination exists): $dst"; $skipped++; continue }

    if ($r.Category -eq 'Duplicate' -and $r.Reference) {
        if (-not (Test-Path -LiteralPath $r.Reference)) { Write-Host "$tag SKIP (kept copy missing, refusing to quarantine the last copy): $($r.Reference)"; $skipped++; continue }
        if ($Apply) {
            Write-Host "$tag verifying full hash..."
            if ((Get-FMFullHash $src) -ne (Get-FMFullHash $r.Reference)) { Write-Host "$tag SKIP (not identical after full hash)"; $skipped++; continue }
        }
    }

    if ($Apply) {
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        try {
            Move-Item -LiteralPath $src -Destination $dst -ErrorAction Stop
            (@{ Action = $r.Action; From = $src; To = $dst } | ConvertTo-Json -Compress) | Add-Content -LiteralPath $undoPath -Encoding UTF8
        } catch { Write-Host "$tag FAILED: $($_.Exception.Message)"; $skipped++; continue }
    }
    Write-Host "$tag $src -> $dst"; $done++
}

Write-Host ""
$verb = if ($Apply) { 'done' } else { 'would change' }
Write-Host "$mode complete: $done $verb, $skipped skipped."
if ($Apply -and $done) { Write-Host "Undo log: $undoPath  (reverse with Undo-FileMasterPlan.ps1 -UndoLog `"$undoPath`")" }
if (-not $Apply) { Write-Host "Nothing changed. Re-run with -Apply to do it." }
