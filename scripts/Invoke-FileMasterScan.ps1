<#
.SYNOPSIS
    Read-only audit of your files, folders, and projects.

.DESCRIPTION
    Walks the folders listed in the config and looks for things that are
    broken, wasteful, or drifting: duplicate copies, partial downloads,
    files missing extensions, piles of installers and logs, empty folders,
    sensitive-looking files in exposed places, unhealthy git repos, and
    new ("emerging") projects that are missing basic setup.

    Nothing is changed. The scan writes three files to reports\<run-id>\:
      report.md      human-readable summary
      findings.json  every finding, machine-readable
      plan.csv       proposed moves/renames. Mark Approved = yes on rows you
                     want, then run Invoke-FileMasterPlan.ps1.

.PARAMETER ConfigPath
    Config file. Defaults to config\file-master.config.local.json if it
    exists, else config\file-master.config.json.

.PARAMETER OutDir
    Where to write the report folder. Defaults to <repo>\reports.

.PARAMETER SkipGit
    Skip git repo health checks (faster).

.EXAMPLE
    .\scripts\Invoke-FileMasterScan.ps1
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$OutDir,
    [switch]$SkipGit
)

. (Join-Path $PSScriptRoot 'lib\FileMaster.Common.ps1')
$ErrorActionPreference = 'Continue'

$cfg = Get-FMConfig $ConfigPath
$runId = Get-Date -Format 'yyyy-MM-dd_HHmm'
if (-not $OutDir) { $OutDir = Join-Path $script:FMRepoRoot 'reports' }
$runDir = Join-Path $OutDir $runId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$roots = @($cfg.roots | ForEach-Object { Expand-FMPath $_ } | Where-Object { Test-Path -LiteralPath $_ })
$projectRoots = @($cfg.projectRoots | ForEach-Object { Expand-FMPath $_ } | Where-Object { Test-Path -LiteralPath $_ })
$skip = @{}; foreach ($s in $cfg.skipDirs) { $skip[$s.ToLowerInvariant()] = $true }
$skipPaths = @($cfg.skipPaths | Where-Object { $_ } | ForEach-Object { Expand-FMPath $_ })
$OutDir = [IO.Path]::GetFullPath($OutDir)
$installerHome = Expand-FMPath $cfg.installerHome
$now = Get-Date

$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding {
    param($Severity, $Category, $Path, $Detail, $Action = 'Review', $Destination = '', $Reference = '', [double]$SizeMB = 0)
    $findings.Add([pscustomobject]@{
        Severity = $Severity; Category = $Category; Path = $Path; Detail = $Detail
        Action = $Action; Destination = $Destination; Reference = $Reference; SizeMB = [math]::Round($SizeMB, 1)
    })
}
function Test-Under { param($Path, $Prefixes) foreach ($p in $Prefixes) { if ($Path.StartsWith($p + '\', 'OrdinalIgnoreCase') -or $Path -ieq $p) { return $true } }; return $false }

# ---------------------------------------------------------------- walk
Write-Host "File Master scan $runId"
Write-Host "Walking $($roots.Count) roots..."
$files = New-Object System.Collections.Generic.List[IO.FileInfo]
$dirs = New-Object System.Collections.Generic.List[object]
$repoRoots = New-Object System.Collections.Generic.List[string]
$unityRoots = New-Object System.Collections.Generic.List[string]
$seen = @{}
$stack = New-Object System.Collections.Generic.Stack[string]
foreach ($r in $roots) { $stack.Push($r) }
while ($stack.Count -gt 0) {
    $d = $stack.Pop()
    if ($seen.ContainsKey($d)) { continue }; $seen[$d] = $true
    try { $entries = ([IO.DirectoryInfo]$d).GetFileSystemInfos() } catch { continue }
    $names = @{}; foreach ($e in $entries) { $names[$e.Name.ToLowerInvariant()] = $true }
    if ($names.ContainsKey('.git')) { $repoRoots.Add($d) }
    if ($names.ContainsKey('assets') -and $names.ContainsKey('projectsettings')) { $unityRoots.Add($d) }
    $dirs.Add([pscustomobject]@{ Path = $d; Count = $entries.Count })
    foreach ($e in $entries) {
        if ($e -is [IO.DirectoryInfo]) {
            if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($skip.ContainsKey($e.Name.ToLowerInvariant())) { continue }
            if ($skipPaths -contains $e.FullName) { continue }
            $stack.Push($e.FullName)
        } else {
            if ($e.Attributes -band [IO.FileAttributes]::System) { continue }
            $files.Add($e)
        }
    }
}
Write-Host ("  {0:N0} files, {1:N0} folders, {2} git repos, {3} Unity projects" -f $files.Count, $dirs.Count, $repoRoots.Count, $unityRoots.Count)
$unityArr = $unityRoots.ToArray(); $repoArr = $repoRoots.ToArray()

# ---------------------------------------------------------------- partial downloads
foreach ($f in $files) {
    if ($f.Extension -match '^\.(opdownload|crdownload|part|partial|download|!ut)$') {
        Add-Finding 'High' 'Partial download' $f.FullName "Unfinished browser/torrent download. Re-download if you still need it." 'Quarantine' (Get-FMHoldingPath $f.FullName $runId $cfg.holdingFolderName) '' ($f.Length / 1MB)
    }
}

# ---------------------------------------------------------------- duplicates
Write-Host "Hashing duplicate candidates..."
$minDup = [long]$cfg.duplicateMinMB * 1MB
$dupWasteMB = 0
$bySize = $files | Where-Object { $_.Length -ge $minDup -and $_.Extension -notmatch '^\.(opdownload|crdownload|part|partial|download)$' } | Group-Object Length | Where-Object Count -gt 1
foreach ($g in $bySize) {
    $hashed = foreach ($f in $g.Group) { try { [pscustomobject]@{ F = $f; H = (Get-FMPartialHash $f.FullName) } } catch { } }
    foreach ($hg in ($hashed | Group-Object H | Where-Object Count -gt 1)) {
        # Keep the copy under a preferred root if configured, else the oldest one.
        $prefer = @($cfg.preferKeepUnder | Where-Object { $_ } | ForEach-Object { Expand-FMPath $_ })
        $copies = $hg.Group | ForEach-Object { $_.F }
        # Prefer: not inside a project (projects hold working copies), then under preferKeepUnder, then oldest.
        $keep = $copies | Sort-Object `
            { if ((Test-Under $_.FullName $unityArr) -or (Test-Under $_.FullName $repoArr)) { 1 } else { 0 } },
            { if ($prefer.Count -and (Test-Under $_.FullName $prefer)) { 0 } else { 1 } },
            CreationTime, { $_.FullName.Length } | Select-Object -First 1
        foreach ($c in $copies) {
            if ($c.FullName -eq $keep.FullName) { continue }
            $dupWasteMB += $c.Length / 1MB
            $inProject = (Test-Under $c.FullName $unityArr) -or (Test-Under $c.FullName $repoArr)
            $action = if ($inProject) { 'Review' } else { 'Quarantine' }
            $why = "Same content as the kept copy. " + $(if ($inProject) { 'Inside a project, so check before removing.' } else { 'Safe to move to holding.' })
            Add-Finding 'Medium' 'Duplicate' $c.FullName $why $action (Get-FMHoldingPath $c.FullName $runId $cfg.holdingFolderName) $keep.FullName ($c.Length / 1MB)
        }
    }
}

# ---------------------------------------------------------------- names and extensions
foreach ($f in $files) {
    $p = $f.FullName
    if (Test-Under $p $unityArr) { continue }
    if ($f.Extension -eq '' -and $f.Length -gt 1KB -and $f.Name -notmatch '^(LICENSE|Makefile|Dockerfile|README|CHANGELOG|version|\.)') {
        $ext = Get-FMMagicExtension $p
        if ($ext) {
            Add-Finding 'High' 'Missing extension' $p "Looks like a $ext file but has no extension, so apps cannot open it by double-click." 'Rename' ($p + $ext) '' ($f.Length / 1MB)
        }
    }
    if ($f.Name -cmatch '^(.*)\.(\w{2,4})\.\2$') {
        Add-Finding 'High' 'Double extension' $p "Extension typed twice (hidden-extension trap)." 'Rename' (Join-Path $f.DirectoryName ($Matches[1] + '.' + $Matches[2])) '' ($f.Length / 1MB)
    }
    $copyish = $f.Name -match '(\s-\sCopy|^Copy of |-(png|jpg|jpeg)\.\2$)'
    if (-not $copyish -and $f.Extension -ne '.meta' -and $f.Name -match '^(.+?)\s?\(\d+\)(\.[^.]+)?$') {
        # "photo (2).jpg" only counts as a copy when "photo.jpg" sits next to it.
        $copyish = [IO.File]::Exists((Join-Path $f.DirectoryName ($Matches[1] + $Matches[2])))
    }
    if ($copyish) {
        Add-Finding 'Low' 'Copy-style name' $p "Name suggests an accidental copy or an export naming slip." 'Review' '' '' ($f.Length / 1MB)
    }
}

# ---------------------------------------------------------------- installers
$installerRe = '(setup|install|installer|_setup|redist|runtime).*\.(exe|msi)$|\.(msi)$'
$installers = @($files | Where-Object { $_.Name -match $installerRe -and -not (Test-Under $_.FullName $unityArr) })
$instDirs = $installers | Group-Object DirectoryName | Where-Object Count -ge 3
foreach ($g in $instDirs) {
    if ($installerHome -and $g.Name -ieq $installerHome) { continue }
    $mb = ($g.Group | Measure-Object Length -Sum).Sum / 1MB
    Add-Finding 'Medium' 'Installer pile' $g.Name "$($g.Count) installers ($([math]::Round($mb)) MB). These can be re-downloaded; keep one folder, outside Documents." 'Review' $installerHome '' $mb
}

# ---------------------------------------------------------------- log piles
$logDirs = $files | Where-Object { $_.Extension -eq '.log' -and $_.Directory.Name -notmatch '^logs?$' } | Group-Object DirectoryName | Where-Object Count -ge $cfg.logPileThreshold
foreach ($g in $logDirs) {
    if (Test-Under $g.Name $unityArr) { continue }
    foreach ($f in $g.Group) {
        Add-Finding 'Low' 'Log pile' $f.FullName "One of $($g.Count) .log files cluttering a project folder." 'Move' (Join-Path (Join-Path $g.Name 'logs') $f.Name) '' ($f.Length / 1MB)
    }
}

# ---------------------------------------------------------------- empty folders
foreach ($d in $dirs) {
    if ($d.Count -ne 0) { continue }
    if ($roots -contains $d.Path) { continue }
    if (Test-Under $d.Path @($OutDir)) { continue }
    if ((Test-Under $d.Path $unityArr) -or (Test-Under $d.Path $repoArr)) { continue }
    Add-Finding 'Low' 'Empty folder' $d.Path "Empty folder." 'RemoveEmpty'
}

# ---------------------------------------------------------------- large files
$big = [long]$cfg.largeFileMB * 1MB
foreach ($f in ($files | Where-Object { $_.Length -ge $big } | Sort-Object Length -Descending | Select-Object -First 40)) {
    Add-Finding 'Info' 'Large file' $f.FullName "Large file. Make sure it lives on the right drive." 'Review' '' '' ($f.Length / 1MB)
}

# ---------------------------------------------------------------- sensitive names in exposed places
$exposed = @($cfg.driveRoots) + @('%USERPROFILE%\Desktop', '%USERPROFILE%\Documents', '%USERPROFILE%\Downloads') | ForEach-Object { Expand-FMPath $_ }
foreach ($e in $exposed) {
    if (-not (Test-Path -LiteralPath $e)) { continue }
    Get-ChildItem -LiteralPath $e -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(key|password|passwd|secret|token|credential|seed|recovery|2fa|backup.?codes)' -or $_.Name -match '^\.env' } |
        Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::System) } |
        ForEach-Object { Add-Finding 'High' 'Sensitive file exposed' $_.FullName "Name suggests a secret stored in plain text in an easy-to-find place. Move it into a password manager, then delete." 'Review' }
}

# ---------------------------------------------------------------- git repos
$repoRows = New-Object System.Collections.Generic.List[object]
function Invoke-FMGit { param([string]$Repo) & git -C $Repo @args 2>$null }
if (-not $SkipGit -and (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Checking $($repoRoots.Count) git repos..."
    foreach ($r in $repoRoots) {
        $hasCommit = [bool](Invoke-FMGit $r 'rev-parse' '--verify' '-q' 'HEAD')
        $remote = (Invoke-FMGit $r 'remote' 'get-url' 'origin')
        $branch = (Invoke-FMGit $r 'branch' '--show-current')
        $dirtyLines = @(Invoke-FMGit $r 'status' '--porcelain')
        $dirty = $dirtyLines.Count
        $upstream = (Invoke-FMGit $r 'rev-parse' '--abbrev-ref' '--symbolic-full-name' '@{u}')
        $ahead = if ($upstream) { [int](Invoke-FMGit $r 'rev-list' '--count' '@{u}..HEAD') } else { $null }
        $last = (Invoke-FMGit $r 'log' '-1' '--format=%cs')
        $hasIgnore = Test-Path -LiteralPath (Join-Path $r '.gitignore')
        $nested = Test-Under (Split-Path $r -Parent) ($repoArr | Where-Object { $_ -ne $r })

        if (-not $hasCommit) { Add-Finding 'High' 'Git: no commits' $r "Repo was created but nothing was ever committed. Git is not protecting any of this work." }
        if (-not $remote) { Add-Finding 'Medium' 'Git: no remote' $r "Not connected to GitHub, so there is no off-PC copy." }
        elseif (-not $upstream -and $hasCommit) { Add-Finding 'Medium' 'Git: branch not tracking' $r "Branch '$branch' has no upstream; run: git push -u origin $branch" }
        if ($ahead -gt 0) { Add-Finding 'Medium' 'Git: unpushed commits' $r "$ahead commit(s) not on GitHub yet." }
        if ($dirty -gt 200) { Add-Finding 'High' 'Git: huge uncommitted change' $r "$dirty uncommitted changes. Commit in small steps or fix .gitignore." }
        elseif ($dirty -gt 0) { Add-Finding 'Low' 'Git: uncommitted changes' $r "$dirty uncommitted change(s)." }
        if (-not $hasIgnore) { Add-Finding 'Medium' 'Git: no .gitignore' $r "No .gitignore, so build output and big assets can get committed by accident." }
        if ($nested) { Add-Finding 'Medium' 'Git: nested repo' $r "Repo inside another repo. The outer repo will not track it properly." }
        if ($remote) {
            $remoteName = ($remote -replace '\.git$', '') -replace '.*/', ''
            $folder = Split-Path $r -Leaf
            if ($remoteName -and $remoteName -ine $folder) { Add-Finding 'Low' 'Git: name mismatch' $r "Folder '$folder' but GitHub repo is '$remoteName'. Rename one so they match." }
        }
        # Large files that are tracked or would be picked up by 'git add .'
        $limit = [long]$cfg.repoLargeFileMB * 1MB
        $cands = @(Invoke-FMGit $r 'ls-files') + @(Invoke-FMGit $r 'ls-files' '-o' '--exclude-standard') | Select-Object -First 20000
        $bigInRepo = 0
        foreach ($rel in $cands) {
            if (-not $rel) { continue }
            $fp = Join-Path $r ($rel -replace '/', '\')
            try { $len = ([IO.FileInfo]$fp).Length } catch { continue }
            if ($len -ge $limit) {
                $bigInRepo++
                if ($bigInRepo -le 10) { Add-Finding 'High' 'Git: large file not ignored' $fp ("{0:N0} MB file is tracked or would be committed. GitHub rejects files over 100 MB; purchased assets must never be pushed." -f ($len / 1MB)) 'Review' '' $r ($len / 1MB) }
            }
        }
        $repoRows.Add([pscustomobject]@{ Repo = $r; Commits = $hasCommit; Remote = $remote; Branch = $branch; Upstream = $upstream; Ahead = $ahead; Dirty = $dirty; Last = $last; BigFiles = $bigInRepo })
    }
}

# ---------------------------------------------------------------- projects
$projRows = New-Object System.Collections.Generic.List[object]
foreach ($pr in $projectRoots) {
    foreach ($p in (Get-ChildItem -LiteralPath $pr -Directory -Force -ErrorAction SilentlyContinue)) {
        $all = @(Get-ChildItem -LiteralPath $p.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(\.git|node_modules)\\' })
        $newest = ($all | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
        $ageDays = [int]($now - $p.CreationTime).TotalDays
        $idleDays = if ($newest) { [int]($now - $newest.LastWriteTime).TotalDays } else { $ageDays }
        $git = Test-Path -LiteralPath (Join-Path $p.FullName '.git')
        $readme = [bool](Get-ChildItem -LiteralPath $p.FullName -Filter 'README*' -File -ErrorAction SilentlyContinue)
        $code = @($all | Where-Object { $_.Extension -match '^\.(js|ts|tsx|py|cs|ps1|html|css|json|md|go|rs|java|cpp|c|h|shader|toml|yml|yaml)$' }).Count
        $media = @($all | Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|gif|webp|mp4|mov|psd|zip|7z|rar|pdf|unitypackage|blend|fbx|)$' }).Count
        $status = if ($ageDays -le $cfg.emergingProjectDays) { 'emerging' } elseif ($idleDays -ge $cfg.staleProjectDays) { 'stale' } else { 'active' }
        $kebab = ConvertTo-FMKebab $p.Name
        $todo = @()
        if (-not $git -and $code -gt 0) { $todo += 'git init + first commit' }
        if (-not $readme) { $todo += 'README (what is this, how to run)' }
        if ($code -eq 0 -and $media -gt 0) { $todo += 'only assets, no code: is this a project or an asset folder?' }
        if ($p.Name -cne $kebab) { $todo += "rename to '$kebab'" }
        $projRows.Add([pscustomobject]@{ Project = $p.Name; Status = $status; AgeDays = $ageDays; IdleDays = $idleDays; Git = $git; Readme = $readme; CodeFiles = $code; MediaFiles = $media; Todo = ($todo -join '; ') })
        if ($status -eq 'emerging' -and $todo.Count) { Add-Finding 'Medium' 'Emerging project setup' $p.FullName ("New project needs: " + ($todo -join '; ')) }
        if ($status -eq 'stale') { Add-Finding 'Low' 'Stale project' $p.FullName "No changes in $idleDays days. Archive it or pick it back up." }
        if ($p.Name -cne $kebab -and -not $git) { Add-Finding 'Low' 'Project naming' $p.FullName "Use lowercase-with-dashes so names are consistent and safe in URLs and scripts." 'Rename' (Join-Path $pr $kebab) }
    }
}
foreach ($r in $repoRoots) {
    if ((Test-Under $r $projectRoots) -or (Test-Under $r $unityArr)) { continue }
    if (Test-Under (Split-Path $r -Parent) ($repoArr | Where-Object { $_ -ne $r })) { continue }
    Add-Finding 'Low' 'Project outside Projects' $r "A git repo outside your project folders. Consider moving it so all projects live in one place." 'Review'
}

# ---------------------------------------------------------------- write outputs
$sevOrder = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
$sorted = @($findings | Sort-Object { $sevOrder[$_.Severity] }, Category, { -$_.SizeMB })
$sorted | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDir 'findings.json') -Encoding UTF8

$i = 0
$planRows = foreach ($f in $sorted) {
    if ($f.Action -notin @('Move', 'Rename', 'Quarantine', 'RemoveEmpty')) { continue }
    $i++
    [pscustomobject]@{ Id = $i; Severity = $f.Severity; Category = $f.Category; Action = $f.Action; Source = $f.Path; Destination = $f.Destination; Reference = $f.Reference; SizeMB = $f.SizeMB; Reason = $f.Detail; Approved = '' }
}
$planPath = Join-Path $runDir 'plan.csv'
@($planRows) | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding UTF8

$md = New-Object System.Text.StringBuilder
function L { param($s = '') [void]$md.AppendLine($s) }
L "# File Master report - $runId"
L
L ("Scanned {0:N0} files in {1:N0} folders across {2} roots. Found {3} git repos and {4} Unity projects." -f $files.Count, $dirs.Count, $roots.Count, $repoRoots.Count, $unityRoots.Count)
L
L "| Severity | Findings |"; L "|---|---|"
foreach ($s in 'High', 'Medium', 'Low', 'Info') { L ("| {0} | {1} |" -f $s, @($sorted | Where-Object Severity -eq $s).Count) }
L
L ("Likely duplicate space: **{0:N1} GB**. Proposed actions in plan.csv: **{1}**." -f ($dupWasteMB / 1024), @($planRows).Count)
L
L "## Projects"
L
L "| Project | Status | Age (d) | Idle (d) | Git | README | To do |"; L "|---|---|---|---|---|---|---|"
foreach ($p in $projRows) { L ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |" -f $p.Project, $p.Status, $p.AgeDays, $p.IdleDays, $(if ($p.Git) { 'yes' } else { 'no' }), $(if ($p.Readme) { 'yes' } else { 'no' }), $p.Todo) }
L
if ($repoRows.Count) {
    L "## Git repos"
    L
    L "| Repo | Commits | Remote | Branch | Ahead | Dirty | Last commit | Big files |"; L "|---|---|---|---|---|---|---|---|"
    foreach ($r in $repoRows) { L ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |" -f $r.Repo, $(if ($r.Commits) { 'yes' } else { '**none**' }), $(if ($r.Remote) { $r.Remote } else { '**none**' }), $r.Branch, $r.Ahead, $r.Dirty, $r.Last, $r.BigFiles) }
    L
}
foreach ($cat in ($sorted | Group-Object Category)) {
    $sev = $cat.Group[0].Severity
    $mb = ($cat.Group | Measure-Object SizeMB -Sum).Sum
    L ("## [{0}] {1} ({2}{3})" -f $sev, $cat.Name, $cat.Count, $(if ($mb -gt 1) { (", {0:N1} GB" -f ($mb / 1024)) } else { '' }))
    L
    foreach ($f in ($cat.Group | Select-Object -First 25)) {
        $extra = if ($f.Destination -and $f.Action -ne 'Quarantine') { " -> ``$($f.Destination)``" }
                 elseif ($f.Reference -and $f.Category -eq 'Duplicate') { " (kept: ``$($f.Reference)``)" }
                 elseif ($f.Reference) { " (repo: ``$($f.Reference)``)" }
                 else { '' }
        $size = if ($f.SizeMB -ge 1) { " ({0:N0} MB)" -f $f.SizeMB } else { '' }
        L ("- ``{0}``{1}{2} - {3}" -f $f.Path, $size, $extra, $f.Detail)
    }
    if ($cat.Count -gt 25) { L "- ...and $($cat.Count - 25) more in findings.json" }
    L
}
L "## Next step"
L
L "Open ``plan.csv``, put ``yes`` in the Approved column for rows you agree with, then run:"
L
L '```powershell'
L ".\scripts\Invoke-FileMasterPlan.ps1 -PlanPath `"$planPath`"          # dry run"
L ".\scripts\Invoke-FileMasterPlan.ps1 -PlanPath `"$planPath`" -Apply   # do it"
L '```'
L
L "Quarantined files go to ``<drive>\$($cfg.holdingFolderName)\$runId\``. Nothing is deleted. Empty that folder yourself once you are sure."
Set-Content -LiteralPath (Join-Path $runDir 'report.md') -Value $md.ToString() -Encoding UTF8

Write-Host ""
Write-Host ("Done. {0} findings ({1} high). Report: {2}" -f $sorted.Count, @($sorted | Where-Object Severity -eq 'High').Count, (Join-Path $runDir 'report.md'))
[pscustomobject]@{ RunId = $runId; ReportPath = (Join-Path $runDir 'report.md'); PlanPath = $planPath; Findings = $sorted.Count; High = @($sorted | Where-Object Severity -eq 'High').Count; DuplicateGB = [math]::Round($dupWasteMB / 1024, 1) }
