<#
.SYNOPSIS
    new-programs-watch (pet-program-12-v1.0-new-programs-watch-v1.0): lists programs that are new on this PC,
    wherever they were installed, newest first.

.DESCRIPTION
    A tool of File Master's pet program. Read only: it never installs, removes or changes anything.

    Looks in four places:
      - the Windows installed-programs list (both 64-bit and 32-bit, machine and user);
      - Start menu shortcuts (machine and user);
      - Microsoft Store apps for this user;
      - with Everything (voidtools) running and es.exe installed: every .exe created in the last
        -Days days anywhere on the PC outside Windows folders, which catches portable programs too.

    Remembers what it has seen in %LOCALAPPDATA%\file-master\known-programs-v1.json. The first run records
    a baseline and lists what was installed in the last -Days days; later runs list everything new since.

    Writes reports\new-programs-<run id>\new-programs.html and new-programs.json (git ignores reports\).

    Downloads (optional, for the whole-PC search): Everything https://www.voidtools.com/downloads/
    and its command-line tool es.exe https://github.com/voidtools/es/releases (or: winget install voidtools.Everything.Cli).

.EXAMPLE
    .\scripts\new-programs-watch-20261013.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir,
    [int]$Days = 30,
    [switch]$NoEverything
)

. (Join-Path $PSScriptRoot 'lib\FileMaster.Common.ps1')
$ErrorActionPreference = 'Continue'
$Label = 'pet-program-12-v1.0-new-programs-watch-v1.0'
$runId = Get-Date -Format 'yyyy-MM-dd_HHmm'
if (-not $OutDir) { $OutDir = Join-Path $script:FMRepoRoot 'reports' }
$runDir = Join-Path $OutDir "new-programs-$runId"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$stateDir = Join-Path $env:LOCALAPPDATA 'file-master'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$statePath = Join-Path $stateDir 'known-programs-v1.json'
$since = (Get-Date).AddDays(-$Days)

$found = New-Object System.Collections.Generic.List[object]
function Add-Program { param($Key, $Name, $Version, $Publisher, $Where, $Source, $Installed)
    if (-not $Name) { return }
    $found.Add([pscustomobject]@{ Key = $Key; Name = $Name; Version = $Version; Publisher = $Publisher; Location = $Where; Source = $Source; Installed = $Installed }) }

# Registry entries leave out values they do not have; read them safely (strict mode is on).
function Get-Prop { param($o, [string]$n) $x = $o.PSObject.Properties[$n]; if ($x) { $x.Value } }

# 1. Installed-programs list
$uninstall = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
foreach ($k in $uninstall) {
    foreach ($p in (Get-ItemProperty $k -ErrorAction SilentlyContinue)) {
        $name = Get-Prop $p 'DisplayName'; if (-not $name -or (Get-Prop $p 'SystemComponent') -eq 1) { continue }
        $installDate = Get-Prop $p 'InstallDate'
        $date = $null; if ($installDate -match '^\d{8}$') { try { $date = [datetime]::ParseExact($installDate, 'yyyyMMdd', $null) } catch { } }
        Add-Program ('uninstall|' + $name) $name (Get-Prop $p 'DisplayVersion') (Get-Prop $p 'Publisher') (Get-Prop $p 'InstallLocation') 'Installed programs' $date
    }
}
# 2. Start menu shortcuts
foreach ($sm in @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")) {
    if (-not (Test-Path -LiteralPath $sm)) { continue }
    foreach ($l in (Get-ChildItem -LiteralPath $sm -Recurse -Filter *.lnk -ErrorAction SilentlyContinue)) {
        if ($l.BaseName -match '^(Uninstall|Readme|Help|Website)') { continue }
        Add-Program ("startmenu|" + $l.BaseName) $l.BaseName '' '' $l.FullName 'Start menu' $l.CreationTime
    }
}
# 3. Microsoft Store apps
foreach ($a in (Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and $_.SignatureKind -ne 'System' })) {
    $date = try { (Get-Item -LiteralPath $a.InstallLocation -ErrorAction Stop).CreationTime } catch { $null }
    Add-Program ("store|" + $a.Name) $a.Name $a.Version $a.Publisher $a.InstallLocation 'Microsoft Store' $date
}
# 4. Everything: new .exe files anywhere (portable programs)
$source = 'installed programs, Start menu, Store apps'
if (-not $NoEverything -and (Get-Process Everything -ErrorAction SilentlyContinue)) {
    $es = (Get-Command es.exe -ErrorAction SilentlyContinue).Source
    foreach ($p in @("$env:ProgramFiles\Everything\es.exe", "${env:ProgramFiles(x86)}\Everything\es.exe")) { if (-not $es -and (Test-Path -LiteralPath $p)) { $es = $p } }
    if ($es) {
        $exes = @(& $es 'ext:exe' "dc:>=$($since.ToString('yyyy-MM-dd'))" '!path:\Windows\' '!path:\$Recycle.Bin\' 2>$null | Select-Object -First 2000)
        foreach ($x in $exes) { $fi = try { [IO.FileInfo]$x } catch { $null }; if ($fi) { Add-Program ("exe|" + $x) $fi.BaseName '' '' $x 'Everything (.exe anywhere)' $fi.CreationTime } }
        $source += ', Everything (whole PC)'
    }
}
$found = @($found | Sort-Object Key -Unique)

# Compare with what was seen before
$known = @{}
$firstRun = -not (Test-Path -LiteralPath $statePath)
if (-not $firstRun) { try { foreach ($k in (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).keys) { $known[$k] = $true } } catch { $firstRun = $true } }
$new = if ($firstRun) { @($found | Where-Object { $_.Installed -and $_.Installed -ge $since }) } else { @($found | Where-Object { -not $known.ContainsKey($_.Key) }) }
$new = @($new | Sort-Object { if ($_.Installed) { $_.Installed } else { [datetime]::MaxValue } } -Descending)
[pscustomobject]@{ tool = $Label; updated = (Get-Date).ToString('s'); keys = @($found | ForEach-Object Key) } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $statePath -Encoding UTF8

# Outputs
$what = if ($firstRun) { "First run: recorded a baseline of $($found.Count) programs. Listing what was installed in the last $Days days." } else { "$($new.Count) new since the last run." }
[pscustomobject]@{ Tool = $Label; Run = $runId; Source = $source; Known = $found.Count; FirstRun = $firstRun
    New = @($new | Select-Object Name, Version, Publisher, Location, Source, @{ n = 'Installed'; e = { if ($_.Installed) { $_.Installed.ToString('yyyy-MM-dd') } } }) } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDir 'new-programs.json') -Encoding UTF8
$enc = { param($s) [Net.WebUtility]::HtmlEncode([string]$s) }
$rowsHtml = foreach ($x in $new) {
    $loc = if ($x.Location -and (Test-Path -LiteralPath $x.Location -ErrorAction SilentlyContinue)) { "<a href=""$(& $enc ([Uri]$x.Location).AbsoluteUri)"">$(& $enc $x.Location)</a>" } else { & $enc $x.Location }
    "<tr><td>$(& $enc $x.Name)</td><td>$(if ($x.Installed) { $x.Installed.ToString('yyyy-MM-dd') })</td><td>$(& $enc $x.Version)</td><td>$(& $enc $x.Publisher)</td><td>$(& $enc $x.Source)</td><td>$loc</td></tr>"
}
$html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>new-programs-watch $runId</title>
<style>
:root{color-scheme:dark;font:15px/1.5 system-ui,sans-serif;background:#17161d;color:#f3f0f7}body{margin:0;padding:24px}
fieldset.toolbox{border:2px solid #d8b4da;border-radius:14px;padding:16px 18px;max-width:1300px;margin:auto}
fieldset.toolbox>legend{font:600 14px ui-monospace,Consolas,monospace;color:#d8b4da;padding:0 8px}
.meta{color:#b6b0c3;margin:0 0 12px}table{border-collapse:collapse;width:100%}th,td{text-align:left;padding:7px 9px;border-bottom:1px solid #3a3544;vertical-align:top}
th{color:#b6b0c3;font-weight:500}a{color:#d8b4da;word-break:break-all}
</style></head><body>
<fieldset class="toolbox"><legend>$Label</legend>
<p class="meta">Data: Astra's PC &middot; run $runId &middot; looked in: $(& $enc $source) &middot; $(& $enc $what) Read only: nothing was changed.</p>
<table><thead><tr><th>Program</th><th>Installed or updated</th><th>Version</th><th>Publisher</th><th>Found in</th><th>Location</th></tr></thead><tbody>
$($rowsHtml -join "`n")
</tbody></table>
</fieldset></body></html>
"@
$htmlPath = Join-Path $runDir 'new-programs.html'
Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8
Write-Host "new-programs-watch: $what Report: $htmlPath"
[pscustomobject]@{ Report = $htmlPath; Known = $found.Count; New = $new.Count; FirstRun = $firstRun; Source = $source }
$global:LASTEXITCODE = 0
