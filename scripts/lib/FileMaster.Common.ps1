# Shared helpers for File Master scripts. Dot-source this file.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+.

Set-StrictMode -Version 2.0

$script:FMRepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Expand-FMPath {
    param([string]$Path)
    if (-not $Path) { return $Path }
    return [Environment]::ExpandEnvironmentVariables($Path).TrimEnd('\') -replace '^([A-Za-z]:)$', '$1\'
}

function Get-FMConfig {
    param([string]$ConfigPath)
    if (-not $ConfigPath) {
        $local = Join-Path $script:FMRepoRoot 'config\file-master.config.local.json'
        $default = Join-Path $script:FMRepoRoot 'config\file-master.config.json'
        $ConfigPath = if (Test-Path -LiteralPath $local) { $local } else { $default }
    }
    $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $cfg | Add-Member -NotePropertyName ConfigPath -NotePropertyValue $ConfigPath -Force
    return $cfg
}

function Get-FMPartialHash {
    # SHA1 of the first and last 1 MB plus the length. Cheap way to find
    # likely duplicates; the apply script re-verifies with a full hash.
    param([string]$Path)
    $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        $sha = [Security.Cryptography.SHA1]::Create()
        $buf = New-Object byte[] 1048576
        $n = $fs.Read($buf, 0, $buf.Length)
        $h = [BitConverter]::ToString($sha.ComputeHash($buf, 0, $n))
        if ($fs.Length -gt 2MB) {
            [void]$fs.Seek(-1048576, 'End')
            $n = $fs.Read($buf, 0, $buf.Length)
            $h += [BitConverter]::ToString($sha.ComputeHash($buf, 0, $n))
        }
        return "$($fs.Length):$h"
    } finally { $fs.Close() }
}

function Get-FMFullHash {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-FMHoldingPath {
    # Where a quarantined item goes: <drive>\_file-master-holding\<runId>\<original path without drive>
    param([string]$Path, [string]$RunId, [string]$HoldingName = '_file-master-holding')
    $qualifier = Split-Path -Qualifier $Path
    $rest = $Path.Substring($qualifier.Length).TrimStart('\')
    return Join-Path (Join-Path (Join-Path "$qualifier\" $HoldingName) $RunId) $rest
}

function ConvertTo-FMKebab {
    param([string]$Name)
    $quotes = "['`"" + [char]0x2019 + "]"
    $n = $Name -replace $quotes, '' -creplace '([a-z0-9])([A-Z])', '$1-$2' -replace '[^A-Za-z0-9]+', '-'
    return $n.Trim('-').ToLowerInvariant()
}

function Get-FMMagicExtension {
    # Detects common formats from the first bytes of a file.
    param([string]$Path)
    try {
        $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try { $b = New-Object byte[] 16; $n = $fs.Read($b, 0, 16) } finally { $fs.Close() }
    } catch { return $null }
    if ($n -lt 8) { return $null }
    $hex = [BitConverter]::ToString($b, 0, $n) -replace '-', ''
    $ascii = [Text.Encoding]::ASCII.GetString($b, 0, $n)
    if ($hex.StartsWith('89504E47')) { return '.png' }
    if ($hex.StartsWith('FFD8FF')) { return '.jpg' }
    if ($ascii.StartsWith('GIF8')) { return '.gif' }
    if ($ascii.StartsWith('%PDF')) { return '.pdf' }
    if ($ascii.StartsWith('RIFF') -and $ascii.Substring(8, 4) -eq 'WEBP') { return '.webp' }
    if ($ascii.StartsWith('RIFF') -and $ascii.Substring(8, 4) -eq 'WAVE') { return '.wav' }
    if ($ascii.Substring(4, 4) -eq 'ftyp') {
        $brand = $ascii.Substring(8, 4)
        if ($brand -match '^(heic|heix|mif1)') { return '.heic' }
        if ($brand -match '^qt') { return '.mov' }
        return '.mp4'
    }
    if ($hex.StartsWith('504B0304')) { return '.zip' }
    if ($hex.StartsWith('377ABCAF271C')) { return '.7z' }
    if ($ascii.StartsWith('Rar!')) { return '.rar' }
    if ($ascii.StartsWith('ID3') -or $hex.StartsWith('FFFB')) { return '.mp3' }
    if ($ascii.StartsWith('OggS')) { return '.ogg' }
    if ($hex.StartsWith('1A45DFA3')) { return '.mkv' }
    return $null
}
