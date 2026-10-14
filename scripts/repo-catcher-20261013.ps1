<#
.SYNOPSIS
    repo-catcher (pet-program-12-v1.0-repo-catcher-v1.0): finds repos on this PC that were never pushed,
    or that hold work GitHub does not have, newest first.

.DESCRIPTION
    A tool of File Master's pet program. Read only: it never commits, pushes, moves or deletes anything.

    Finds every git repo:
      - anywhere on the PC, through Everything (voidtools) when Everything is running and its
        command-line tool es.exe is installed;
      - otherwise by walking the folders in the config plus every other fixed drive.

    Lists each repo that is not safely on GitHub: no commits, no remote, a branch that was never pushed,
    commits not pushed, branches with no upstream, or uncommitted changes. Repos with no change for
    staleProjectDays (config) are marked stale.

    Writes reports\repo-catcher-<run id>\repo-catcher.html and repo-catcher.json. Each row starts with
    the folder location (click it to open the folder), then the date the folder was created; newest first.
    The report holds personal paths, so it stays in reports\, which git ignores.

    Downloads (optional, for the whole-PC search): Everything https://www.voidtools.com/downloads/
    and its command-line tool es.exe https://github.com/voidtools/es/releases (or: winget install voidtools.Everything.Cli).

.PARAMETER All
    Also list repos that are fully pushed and clean.

.EXAMPLE
    .\scripts\repo-catcher-20261013.ps1
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$OutDir,
    [switch]$All,
    [switch]$NoEverything
)

. (Join-Path $PSScriptRoot 'lib\FileMaster.Common.ps1')
$ErrorActionPreference = 'Continue'
$Label = 'pet-program-12-v1.0-repo-catcher-v1.0'

$cfg = Get-FMConfig $ConfigPath
$runId = Get-Date -Format 'yyyy-MM-dd_HHmm'
if (-not $OutDir) { $OutDir = Join-Path $script:FMRepoRoot 'reports' }
$runDir = Join-Path $OutDir "repo-catcher-$runId"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$now = Get-Date
$staleDays = if ($cfg.staleProjectDays) { [int]$cfg.staleProjectDays } else { 60 }
$skip = @{}; foreach ($s in $cfg.skipDirs) { $skip[$s.ToLowerInvariant()] = $true }; $skip.Remove('.git')

# ---------------------------------------------------------------- find repos
function Find-EsExe {
    $c = Get-Command es.exe -ErrorAction SilentlyContinue; if ($c) { return $c.Source }
    foreach ($p in @("$env:ProgramFiles\Everything\es.exe", "${env:ProgramFiles(x86)}\Everything\es.exe", "$env:LOCALAPPDATA\Programs\Everything\es.exe")) { if (Test-Path -LiteralPath $p) { return $p } }
    return $null
}
$repoRoots = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
$source = 'folder walk'
$es = if ($NoEverything) { $null } else { Find-EsExe }
if ($es -and (Get-Process Everything -ErrorAction SilentlyContinue)) {
    $gitDirs = @(& $es 'folder:' 'wfn:.git' 2>$null)
    if ($LASTEXITCODE -eq 0 -and $gitDirs.Count) {
        foreach ($g in $gitDirs) { $parent = Split-Path $g -Parent; if ($parent -and $parent -notmatch '\\(node_modules|\$RECYCLE\.BIN)\\') { [void]$repoRoots.Add($parent) } }
        $source = 'Everything (whole PC)'
    }
}
if ($source -eq 'folder walk') {
    $starts = @($cfg.roots) + @($cfg.projectRoots) | ForEach-Object { Expand-FMPath $_ } | Where-Object { Test-Path -LiteralPath $_ }
    $starts += @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | Where-Object { $_.DeviceID -ne $env:SystemDrive } | ForEach-Object { $_.DeviceID + '\' })
    $maxDepth = if ($cfg.maxGitScanDepth) { [int]$cfg.maxGitScanDepth + 2 } else { 7 }
    $seen = @{}
    $stack = New-Object System.Collections.Generic.Stack[object]
    foreach ($r in $starts) { $stack.Push(@($r, 0)) }
    while ($stack.Count -gt 0) {
        $d, $depth = $stack.Pop()
        if ($seen.ContainsKey($d)) { continue }; $seen[$d] = $true
        try { $entries = ([IO.DirectoryInfo]$d).GetDirectories() } catch { continue }
        if ($entries | Where-Object Name -eq '.git') { [void]$repoRoots.Add($d) }
        if ($depth -ge $maxDepth) { continue }
        foreach ($e in $entries) {
            if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($e.Name -eq '.git' -or $skip.ContainsKey($e.Name.ToLowerInvariant())) { continue }
            $stack.Push(@($e.FullName, ($depth + 1)))
        }
    }
}
Write-Host "repo-catcher: $($repoRoots.Count) repos found by $source"

# ---------------------------------------------------------------- check each repo
function G { param([string]$Repo) & git -C $Repo @args 2>$null }
$rows = New-Object System.Collections.Generic.List[object]
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Warning 'git is not installed, so repos cannot be checked.' }
foreach ($r in $repoRoots) {
    $why = New-Object System.Collections.Generic.List[string]
    $hasCommit = [bool](G $r 'rev-parse' '--verify' '-q' 'HEAD')
    $remote = G $r 'remote' 'get-url' 'origin'
    $branch = G $r 'branch' '--show-current'
    $upstream = G $r 'rev-parse' '--abbrev-ref' '--symbolic-full-name' '@{u}'
    $ahead = if ($upstream) { [int](G $r 'rev-list' '--count' '@{u}..HEAD') } else { 0 }
    $dirty = @(G $r 'status' '--porcelain').Count
    $noUpstream = @(G $r 'for-each-ref' '--format=%(refname:short) %(upstream)' 'refs/heads' | Where-Object { $_ -match '^\S+ $' }).Count
    $lastCommit = G $r 'log' '-1' '--format=%cI'
    if (-not $hasCommit) { $why.Add('no commits: git is not protecting this work') }
    if (-not $remote) { $why.Add('no remote: never connected to GitHub') }
    elseif ($hasCommit -and -not $upstream) { $why.Add("branch '$branch' was never pushed") }
    if ($ahead -gt 0) { $why.Add("$ahead commit(s) not pushed") }
    if ($noUpstream -gt 0 -and $upstream) { $why.Add("$noUpstream other branch(es) with no upstream") }
    if ($dirty -gt 0) { $why.Add("$dirty uncommitted change(s)") }
    try { $created = ([IO.DirectoryInfo]$r).CreationTime } catch { $created = $null }
    $lastChange = if ($lastCommit) { [datetime]$lastCommit } else { try { ([IO.DirectoryInfo]$r).LastWriteTime } catch { $null } }
    $idle = if ($lastChange) { [int]($now - $lastChange).TotalDays } else { $null }
    $stale = $idle -ne $null -and $idle -ge $staleDays
    if (-not $why.Count -and -not $All) { continue }
    $status = if (-not $why.Count) { 'pushed' } elseif ($stale) { 'stale, not pushed' } else { 'not pushed' }
    $rows.Add([pscustomobject]@{
        Location = $r; Url = ([Uri]$r).AbsoluteUri; Created = if ($created) { $created.ToString('yyyy-MM-dd') } else { '' }
        CreatedSort = $created; LastChange = if ($lastChange) { $lastChange.ToString('yyyy-MM-dd') } else { '' }; IdleDays = $idle
        Status = $status; Remote = $remote; Branch = $branch; Why = ($why -join '; ')
    })
}
$sorted = @($rows | Sort-Object CreatedSort -Descending)

# ---------------------------------------------------------------- write outputs
$meta = [pscustomobject]@{ Tool = $Label; Run = $runId; Source = $source; Repos = $repoRoots.Count; Listed = $sorted.Count; StaleDays = $staleDays }
[pscustomobject]@{ Meta = $meta; Rows = @($sorted | Select-Object Location, Url, Created, LastChange, IdleDays, Status, Remote, Branch, Why) } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDir 'repo-catcher.json') -Encoding UTF8

$enc = { param($s) [Net.WebUtility]::HtmlEncode([string]$s) }
$rowsHtml = foreach ($x in $sorted) {
    $cls = if ($x.Status -like 'stale*') { 'stale' } elseif ($x.Status -eq 'pushed') { 'ok' } else { 'warn' }
    "<tr class=""$cls""><td><a href=""$(& $enc $x.Url)"">$(& $enc $x.Location)</a> <button type=""button"" data-path=""$(& $enc $x.Location)"">Copy path</button></td><td>$(& $enc $x.Created)</td><td>$(& $enc $x.LastChange)</td><td>$(& $enc $x.Status)</td><td>$(& $enc $x.Why)</td></tr>"
}
$html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>repo-catcher $runId</title>
<style>
:root{color-scheme:dark;font:15px/1.5 system-ui,sans-serif;background:#17161d;color:#f3f0f7}body{margin:0;padding:24px}
fieldset.toolbox{border:2px solid #d8b4da;border-radius:14px;padding:16px 18px;max-width:1300px;margin:auto}
fieldset.toolbox>legend{font:600 14px ui-monospace,Consolas,monospace;color:#d8b4da;padding:0 8px}
.meta{color:#b6b0c3;margin:0 0 12px}table{border-collapse:collapse;width:100%}th,td{text-align:left;padding:7px 9px;border-bottom:1px solid #3a3544;vertical-align:top}
th{color:#b6b0c3;font-weight:500}a{color:#d8b4da;word-break:break-all}tr.stale td:nth-child(4){color:#ffb86b}tr.warn td:nth-child(4){color:#ff9ecb}tr.ok td:nth-child(4){color:#9fe0b0}
button{font:inherit;font-size:12px;margin-left:6px;background:none;color:#b6b0c3;border:1px solid #62586c;border-radius:6px;cursor:pointer}
</style></head><body>
<fieldset class="toolbox"><legend>$Label</legend>
<p class="meta">Data: Astra's PC &middot; run $runId &middot; found $($repoRoots.Count) repos by $(& $enc $source) &middot; $($sorted.Count) listed, newest first &middot; stale = no change for $staleDays days. Read only: nothing was changed.</p>
<table><thead><tr><th>Location (click to open)</th><th>Created</th><th>Last change</th><th>Status</th><th>Why</th></tr></thead><tbody>
$($rowsHtml -join "`n")
</tbody></table>
</fieldset>
<script>document.addEventListener('click',e=>{const p=e.target.dataset&&e.target.dataset.path;if(p){navigator.clipboard.writeText(p);e.target.textContent='Copied';}});</script>
</body></html>
"@
$htmlPath = Join-Path $runDir 'repo-catcher.html'
Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8
Write-Host "repo-catcher: $($sorted.Count) repos listed. Report: $htmlPath"
[pscustomobject]@{ Report = $htmlPath; Repos = $repoRoots.Count; Listed = $sorted.Count; Source = $source }
$global:LASTEXITCODE = 0
