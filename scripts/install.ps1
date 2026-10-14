#!/usr/bin/env pwsh
<#
Copy-install home/ into the Copilot CLI home directory. PowerShell 7+.

  scripts/install.ps1 -DryRun   show what would change
  scripts/install.ps1           install; changed files are backed up first

Target: $env:COPILOT_HOME if set, otherwise ~/.copilot.
Only files under home/ are written. Nothing else in the target is touched or deleted.
Backups go to <target>/.backup/<timestamp>/ mirroring the original paths.
#>
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'

$src = Join-Path (Split-Path -Parent $PSScriptRoot) 'home'
# The OS profile folder, which is what Copilot uses; $HOME can differ on Windows.
$userHome = [Environment]::GetFolderPath('UserProfile')
$dest = [System.IO.Path]::GetFullPath($(if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $userHome '.copilot' }))
if ($dest -match '[$`"]') {
    Write-Error ('install: the target path contains $, a backtick, or a double quote, which would break the rendered hook command: ' + $dest)
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $dest ".backup/$stamp"
# Forward slashes work on every platform and need no escaping inside JSON hook configs.
$destForFiles = $dest -replace '\\', '/'

Write-Output "Source: $src"
Write-Output "Target: $dest"
if ($DryRun) { Write-Output '(dry run: no changes)' }
Write-Output ''

$added = 0; $updated = 0; $unchanged = 0

Get-ChildItem -LiteralPath $src -Recurse -File | Where-Object Name -ne '.DS_Store' | Sort-Object FullName | ForEach-Object {
    $rel = [System.IO.Path]::GetRelativePath($src, $_.FullName) -replace '\\', '/'
    $dst = Join-Path $dest $rel

    # Render: substitute the install location into hook configs.
    $content = (Get-Content -LiteralPath $_.FullName -Raw) -replace '__COPILOT_HOME__', $destForFiles

    if (-not (Test-Path -LiteralPath $dst)) {
        Write-Output "  add     $rel"
        $added++
    } elseif ((Get-Content -LiteralPath $dst -Raw) -ceq $content) {
        $unchanged++
        return
    } else {
        Write-Output "  update  $rel   (backup: .backup/$stamp/$rel)"
        $updated++
        if (-not $DryRun) {
            $bak = Join-Path $backup $rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bak) | Out-Null
            Copy-Item -LiteralPath $dst -Destination $bak
        }
    }

    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
        [System.IO.File]::WriteAllText($dst, $content, [System.Text.UTF8Encoding]::new($false))
    }
}

Write-Output ''
Write-Output "added: $added  updated: $updated  unchanged: $unchanged"
if (-not $DryRun -and ($added + $updated) -gt 0) {
    Write-Output 'Start a new Copilot CLI session for instruction and hook changes to take effect.'
}
