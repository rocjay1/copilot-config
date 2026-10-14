#!/usr/bin/env pwsh
<#
.SYNOPSIS
Launch Copilot CLI with an explicit permission profile. PowerShell 7+, Windows/macOS/Linux.

.DESCRIPTION
  cop [work|research] [--dry-run] [copilot args...]

  work      (default) The reads below run without prompting. Everything else prompts as
            usual: file edits, pushes, PRs, ticket changes.
  research  Same reads. File edits and the listed external writes are denied outright;
            any other shell command still prompts, so read what you approve.

The profile must be the first argument. Any other bare word there is an error, so a typo
can't silently fall back to work.

Site-specific tools (MCP servers, your own CLIs) come from cop.psd1: $env:COP_CONF if set,
otherwise <COPILOT_HOME or ~/.copilot>/cop.psd1. Start from templates/cop.psd1.example.

--dry-run prints the copilot command this would run, one argument per line, and exits.

Refuses flags that pre-approve everything or let the model approve its own prompts
(--allow-all*, --yolo, --autopilot, --mode autopilot, --assisted-approval), and clears the
environment variables that do the same (COPILOT_ALLOW_ALL, COPILOT_ASSISTED_APPROVAL). Run
`copilot` directly if you really mean it.

No param() block on purpose: every other argument, including -p, passes through to copilot.
#>

$ErrorActionPreference = 'Stop'

function Stop-Cop([string]$msg) { [Console]::Error.WriteLine("cop: $msg"); exit 2 }

$rest = [System.Collections.Generic.List[string]]::new()
foreach ($a in $args) { $rest.Add([string]$a) }

$profileName = 'work'
if ($rest.Count -gt 0) {
    $first = $rest[0]
    if ($first -in 'work', 'research') {
        $profileName = $first; $rest.RemoveAt(0)
    } elseif ($first -in '-h', '--help', '-?') {
        Get-Help $PSCommandPath -Full | Out-String | Write-Output
        exit 0
    } elseif (-not $first.StartsWith('-')) {
        Stop-Cop "unknown profile '$first' (expected work or research; use -p for a prompt)"
    }
}

$refuse = '^--(allow-all(-tools|-paths|-urls)?|yolo|autopilot|assisted-approval)(=.*)?$'
$dryRun = $false
$passthru = [System.Collections.Generic.List[string]]::new()
$prev = ''
foreach ($a in $rest) {
    if ($a -eq '--dry-run') { $dryRun = $true }
    elseif ($a -match $refuse -or $a -match '^--mode=autopilot$' -or ($prev -eq '--mode' -and $a -eq 'autopilot')) {
        Stop-Cop "refusing $a. Run copilot directly if you really mean it."
    }
    elseif ($a -in 'work', 'research') {
        Stop-Cop "the profile must be the first argument (got '$a' later on)"
    }
    else { $passthru.Add($a) }
    $prev = $a
}

foreach ($var in 'COPILOT_ALLOW_ALL', 'COPILOT_ASSISTED_APPROVAL') {
    if ([Environment]::GetEnvironmentVariable($var)) {
        [Console]::Error.WriteLine("cop: ignoring $var for this session")
        [Environment]::SetEnvironmentVariable($var, $null)
    }
}

# Reads that never change anything. git and gh match on the first-level subcommand.
# Left out on purpose: `git branch` and `gh api`, which can also write. The guardrail hook
# blocks `git ... --output`, the one way these git reads can write a file.
$readTools = [System.Collections.Generic.List[string]]@(
    'shell(git status)', 'shell(git diff)', 'shell(git log)', 'shell(git show)',
    'shell(gh pr view)', 'shell(gh pr list)', 'shell(gh pr diff)', 'shell(gh pr checks)',
    'shell(gh issue view)', 'shell(gh issue list)',
    'shell(gh run view)', 'shell(gh run list)'
)

# Denied in research. Deny rules beat allow rules, even a later /allow-all or a saved approval.
$researchDeny = [System.Collections.Generic.List[string]]@(
    'write',
    'shell(git push)', 'shell(git commit)', 'shell(git worktree)', 'shell(git reset)',
    'shell(git clean)', 'shell(git checkout)', 'shell(git switch)', 'shell(git restore)',
    'shell(git stash)', 'shell(git tag)', 'shell(git remote)', 'shell(git config)',
    'shell(git branch)', 'shell(git merge)', 'shell(git rebase)',
    'shell(gh pr create)', 'shell(gh pr merge)', 'shell(gh pr comment)', 'shell(gh pr edit)',
    'shell(gh pr review)', 'shell(gh pr close)', 'shell(gh pr ready)', 'shell(gh pr reopen)',
    'shell(gh issue create)', 'shell(gh issue comment)', 'shell(gh issue edit)',
    'shell(gh issue close)', 'shell(gh issue delete)', 'shell(gh issue reopen)',
    'shell(gh release:*)', 'shell(gh workflow:*)', 'shell(gh repo:*)', 'shell(gh secret:*)',
    'shell(gh variable:*)', 'shell(gh gist:*)', 'shell(gh label:*)',
    'shell(gh api)'
)

if ($env:COP_CONF) {
    if (-not (Test-Path -LiteralPath $env:COP_CONF -PathType Leaf)) { Stop-Cop "COP_CONF=$env:COP_CONF not found" }
    $conf = $env:COP_CONF
} else {
    $userHome = [Environment]::GetFolderPath('UserProfile')
    $copilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $userHome '.copilot' }
    $conf = Join-Path $copilotHome 'cop.psd1'
}

if (Test-Path -LiteralPath $conf -PathType Leaf) {
    # A data file: Import-PowerShellDataFile evaluates no code.
    $data = Import-PowerShellDataFile -LiteralPath $conf
    foreach ($key in $data.Keys) {
        if ($key -notin 'ReadTools', 'ResearchDeny') { Stop-Cop "unknown key '$key' in $conf (expected ReadTools, ResearchDeny)" }
    }
    foreach ($t in @($data.ReadTools)) { if ($t) { $readTools.Add([string]$t) } }
    foreach ($t in @($data.ResearchDeny)) { if ($t) { $researchDeny.Add([string]$t) } }
} else {
    [Console]::Error.WriteLine("cop: no $conf; MCP and custom CLI reads will prompt (see templates/cop.psd1.example)")
}

$copilotArgs = [System.Collections.Generic.List[string]]::new()
foreach ($t in $readTools) { $copilotArgs.Add("--allow-tool=$t") }
if ($profileName -eq 'research') {
    foreach ($t in $researchDeny) { $copilotArgs.Add("--deny-tool=$t") }
}
$copilotArgs.AddRange($passthru)

if ($dryRun) {
    Write-Output "# profile: $profileName   conf: $conf"
    Write-Output 'copilot'
    $copilotArgs | Write-Output
    exit 0
}

& copilot @copilotArgs
exit $LASTEXITCODE
