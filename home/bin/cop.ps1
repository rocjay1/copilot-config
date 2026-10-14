#!/usr/bin/env pwsh
<#
.SYNOPSIS
Launch Copilot CLI with an explicit permission profile. PowerShell 7+, Windows/macOS/Linux.

.DESCRIPTION
  cop [work|research] [--dry-run] [copilot args...]

  work      (default) The reads below and local file edits run without prompting.
            Everything else prompts: pushes, PRs, ticket changes, unlisted commands.
  research  Same reads. File edits and the listed external writes are denied outright;
            any other shell command still prompts, so read what you approve.

Inside a session, /permissions allow-all, /permissions assisted, and /autopilot undo the work
profile's prompts and batching. Research's deny rules and the guardrail hook still hold.

The profile must be the first argument. Any other bare word there is an error, so a typo
can't silently fall back to work.

Site-specific tools (MCP servers, your own CLIs) come from cop.psd1: $env:COP_CONF if set,
otherwise <COPILOT_HOME or ~/.copilot>/cop.psd1. Start from templates/cop.psd1.example.

Each session starts on Auto, balance tier (--model auto --auto-tier balance); set Model in
cop.psd1 to change it, or pass --model yourself. /model still switches mid-session.

Each session gets a soft cap of 100 AI credits (--max-ai-credits). Set MaxAiCredits in cop.psd1
to change it (0 turns it off), pass --max-ai-credits yourself, or raise it in-session with /limits.

--dry-run prints the copilot command this would run, one argument per line, and exits.
--check-notes reports whether NOTES.md is current (exit 0) or out of date (exit 1).

When an interactive work session ends (/exit or Ctrl+C), cop checks NOTES.md against the
handoff fingerprint and, if it's out of date, offers to run the handoff skill in that session,
on a cheap model (HandoffModel in cop.psd1). When a research session ends, it prints how to
continue that session with work permissions.

Refuses flags that pre-approve everything or let the model approve its own prompts
(--allow-all*, --yolo, --autopilot, --mode autopilot, --assisted-approval), and clears the
environment variables that do the same (COPILOT_ALLOW_ALL, COPILOT_ASSISTED_APPROVAL). Run
`copilot` directly if you really mean it.

No param() block on purpose: every other argument, including -p, passes through to copilot.
PowerShell splits an argument that starts with - and contains a colon (-name:value syntax),
so put rules like shell(git:*) in cop.psd1 rather than on the command line.
#>

$ErrorActionPreference = 'Stop'

function Stop-Cop([string]$msg) { [Console]::Error.WriteLine("cop: $msg"); exit 2 }

# Is NOTES.md out of date? Compares the uncommitted files and their hashes against the State
# fingerprint the handoff skill writes. Returns Stale and a short Reason.
function Get-NotesStatus {
    $root = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $root) { return [pscustomobject]@{ Stale = $false; Reason = 'not a git repository' } }
    $raw = (& git -C $root status --porcelain=v1 -z --untracked-files=all 2>$null) -join "`n"
    $entries = @($raw -split "`0" | Where-Object { $_ })
    $current = [ordered]@{}
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $xy = $entries[$i].Substring(0, 2); $path = $entries[$i].Substring(3)
        if ($xy[0] -in 'R', 'C') { $i++ }   # with -z, the original path of a rename comes next
        if ($path -eq 'NOTES.md') { continue }
        $current[$path] = if ($xy -match 'D') { 'deleted' } else { $null }
    }
    $toHash = @($current.Keys | Where-Object { -not $current[$_] })
    if ($toHash.Count) {
        $hashes = @(& git -C $root hash-object -- @toHash)
        for ($i = 0; $i -lt $toHash.Count; $i++) { $current[$toHash[$i]] = $hashes[$i].Substring(0, 7) }
    }

    $notes = Join-Path $root 'NOTES.md'
    if (-not (Test-Path -LiteralPath $notes)) {
        if ($current.Count -eq 0) { return [pscustomobject]@{ Stale = $false; Reason = 'nothing uncommitted and no NOTES.md' } }
        return [pscustomobject]@{ Stale = $true; Reason = "$($current.Count) uncommitted files and no NOTES.md" }
    }
    $recorded = @{}; $recordedHead = $null; $inState = $false; $hasState = $false
    foreach ($line in Get-Content -LiteralPath $notes) {
        if ($line -match '^##\s+State\b') { $inState = $true; $hasState = $true; continue }
        if ($line -match '^##\s') { $inState = $false; continue }
        # "- HEAD abc1234" (current format) or "- clean at abc1234" (older notes)
        if ($inState -and $line -match '^\s*-\s*(?:HEAD|clean at)\s+`?([0-9a-f]{7,40})') {
            $recordedHead = $Matches[1].Substring(0, 7); continue
        }
        if ($inState -and $line -match '^\s*-\s*`([^`]+)`.*?\b([0-9a-f]{7,40}|deleted)\b') {
            $recorded[$Matches[1]] = if ($Matches[2] -eq 'deleted') { 'deleted' } else { $Matches[2].Substring(0, 7) }
        }
    }
    if (-not $hasState) { return [pscustomobject]@{ Stale = $true; Reason = 'NOTES.md has no State section' } }
    if ($recordedHead) {
        $head = & git -C $root rev-parse --short=7 HEAD 2>$null
        if ($head -and -not "$head".StartsWith($recordedHead)) {
            return [pscustomobject]@{ Stale = $true; Reason = "new commits since the last handoff ($recordedHead -> $head)" }
        }
    }
    $changed = @($current.Keys | Where-Object { $recorded[$_] -ne $current[$_] })
    $gone = @($recorded.Keys | Where-Object { -not $current.Contains($_) })
    $n = $changed.Count + $gone.Count
    if ($n -eq 0) { return [pscustomobject]@{ Stale = $false; Reason = 'matches the State fingerprint' } }
    return [pscustomobject]@{ Stale = $true; Reason = "$n files changed since the last handoff" }
}

if ($args.Count -gt 0 -and $args[0] -eq '--check-notes') {
    $s = Get-NotesStatus
    Write-Output ("{0}: {1}" -f ($s.Stale ? 'stale' : 'current'), $s.Reason)
    exit ($s.Stale ? 1 : 0)
}

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

# Reads that never change anything. git rules match the first-level subcommand; gh rules
# need the :* prefix form for deeper subcommands (gh pr view:*).
# Left out on purpose: `git branch` and `gh api`, which can also write. The guardrail hook
# blocks `git ... --output`, the one way these git reads can write a file.
$readTools = [System.Collections.Generic.List[string]]@(
    'shell(git status)', 'shell(git diff)', 'shell(git log)', 'shell(git show)',
    'shell(gh pr view:*)', 'shell(gh pr list:*)', 'shell(gh pr diff:*)', 'shell(gh pr checks:*)',
    'shell(gh issue view:*)', 'shell(gh issue list:*)',
    'shell(gh run view:*)', 'shell(gh run list:*)', 'shell(git hash-object)',
    # Read-only file utilities (bash, then PowerShell). Left out on purpose because they can
    # write: sort -o, tree -o, find -delete/-exec, tee. printf and echo can't write on their own.
    # Shell redirection (cat x > y) is covered by the work profile's `write` approval only inside
    # the working folder, and never approves the command itself (tests/smoke.ps1 W9, W10).
    'shell(cat)', 'shell(ls)', 'shell(head)', 'shell(tail)', 'shell(wc)', 'shell(grep)',
    'shell(pwd)', 'shell(diff)', 'shell(rg)', 'shell(printf)', 'shell(echo)',
    # tf-check runs only read-only Terraform commands (fmt -check, validate, version, providers);
    # plan, init, test, and the rest still go through terraform and prompt.
    'shell(tf-check)',
    'shell(Get-Content)', 'shell(Get-ChildItem)', 'shell(Select-String)', 'shell(Test-Path)',
    'shell(Get-Item)', 'shell(Get-Location)', 'shell(Resolve-Path)'
)

# Pre-approved in work only. File edits stop prompting one by one; you review each batch's
# diff instead (the batching rule in the personal instructions). Research denies writes.
$workAllow = [System.Collections.Generic.List[string]]@('write')

# Denied in research. Deny rules beat allow rules, even a later /allow-all or a saved approval.
$researchDeny = [System.Collections.Generic.List[string]]@(
    'write',
    'shell(git push)', 'shell(git commit)', 'shell(git worktree)', 'shell(git reset)',
    'shell(git clean)', 'shell(git checkout)', 'shell(git switch)', 'shell(git restore)',
    'shell(git stash)', 'shell(git tag)', 'shell(git remote)', 'shell(git config)',
    'shell(git branch)', 'shell(git merge)', 'shell(git rebase)',
    # gh rules need the :* prefix form; Copilot matches `gh pr create` as `gh pr`, so an exact
    # 'shell(gh pr create)' never matches (tests/smoke.ps1 R7).
    'shell(gh pr create:*)', 'shell(gh pr merge:*)', 'shell(gh pr comment:*)', 'shell(gh pr edit:*)',
    'shell(gh pr review:*)', 'shell(gh pr close:*)', 'shell(gh pr ready:*)', 'shell(gh pr reopen:*)',
    'shell(gh issue create:*)', 'shell(gh issue comment:*)', 'shell(gh issue edit:*)',
    'shell(gh issue close:*)', 'shell(gh issue delete:*)', 'shell(gh issue reopen:*)',
    'shell(gh release:*)', 'shell(gh workflow:*)', 'shell(gh repo:*)', 'shell(gh secret:*)',
    'shell(gh variable:*)', 'shell(gh gist:*)', 'shell(gh label:*)',
    'shell(gh api:*)'
)

# Soft cap on AI credits per session (Copilot blocks the next model call once it's exceeded;
# raise it mid-session with /limits). MaxAiCredits in cop.psd1 overrides it; 0 turns it off.
$maxAiCredits = 100

# Model for the handoff cop offers after a work session. The resumed run has to rebuild the
# prompt cache, so a cheap model matters: 'auto-efficiency' (Copilot's cheapest suitable model)
# cost about 0.5 AI credits against 4-14 on the session's model. Any model id works, or
# 'session' to keep the session's model. Set HandoffModel in cop.psd1 to change it.
$handoffModel = 'auto-efficiency'

# Model every cop session starts on: 'auto-balance' (Auto, balance tier), 'auto-efficiency',
# 'auto-intelligence', a model id, or '' to use Copilot's own saved setting. /model still changes
# it mid-session. Set Model in cop.psd1 to change it.
$model = 'auto-balance'

# --model/--auto-tier arguments for a model setting.
function Get-ModelArgs([string]$m) {
    if (-not $m -or $m -eq 'session') { return @() }
    if ($m -match '^auto-(\w+)$') { return @('--model', 'auto', '--auto-tier', $Matches[1]) }
    return @('--model', $m)
}

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
        if ($key -notin 'ReadTools', 'ResearchDeny', 'MaxAiCredits', 'HandoffModel', 'Model') { Stop-Cop "unknown key '$key' in $conf (expected ReadTools, ResearchDeny, MaxAiCredits, HandoffModel, Model)" }
    }
    if ($data.Contains('Model')) { $model = [string]$data.Model }
    if ($data.Contains('MaxAiCredits')) { $maxAiCredits = [int]$data.MaxAiCredits }
    if ($data.Contains('HandoffModel')) { $handoffModel = [string]$data.HandoffModel }
    foreach ($t in @($data.ReadTools)) { if ($t) { $readTools.Add([string]$t) } }
    foreach ($t in @($data.ResearchDeny)) { if ($t) { $researchDeny.Add([string]$t) } }
} else {
    [Console]::Error.WriteLine("cop: no $conf; MCP and custom CLI reads will prompt (see templates/cop.psd1.example)")
}

$copilotArgs = [System.Collections.Generic.List[string]]::new()
foreach ($t in $readTools) { $copilotArgs.Add("--allow-tool=$t") }
if ($profileName -eq 'research') {
    foreach ($t in $researchDeny) { $copilotArgs.Add("--deny-tool=$t") }
} else {
    foreach ($t in $workAllow) { $copilotArgs.Add("--allow-tool=$t") }
}
$permissionArgs = @($copilotArgs)
$ownLimit = @($passthru | Where-Object { $_ -match '^--max-ai-credits(=.*)?$' }).Count -gt 0
if ($maxAiCredits -gt 0 -and -not $ownLimit) {
    if ($maxAiCredits -lt 30) { Stop-Cop "MaxAiCredits must be 0 (off) or at least 30, Copilot's minimum (got $maxAiCredits)" }
    $copilotArgs.Add('--max-ai-credits'); $copilotArgs.Add("$maxAiCredits")
}
$ownModel = @($passthru | Where-Object { $_ -match '^--(model|auto-tier)(=.*)?$' }).Count -gt 0
if (-not $ownModel) { foreach ($a in (Get-ModelArgs $model)) { $copilotArgs.Add($a) } }
$copilotArgs.AddRange($passthru)

# For an interactive session that cop starts itself, pin its session ID. Afterwards:
# - work: if NOTES.md is out of date, offer to run the handoff skill in that same session
#   (copilot --resume <id> -p), with the session's context;
# - research: print how to continue the same session with work permissions.
$isPrompt = @($passthru | Where-Object { $_ -in '-p', '--prompt' -or $_ -like '--prompt=*' }).Count -gt 0
$ownsSession = @($passthru | Where-Object { $_ -match '^(-r|--resume|--continue|--session-id)(=.*)?$' }).Count -eq 0
$pinSession = -not $isPrompt -and $ownsSession -and -not [Console]::IsInputRedirected
$offerHandoff = $pinSession -and $profileName -eq 'work'
if ($pinSession) {
    $sessionId = [guid]::NewGuid().ToString()
    $copilotArgs.Add('--session-id'); $copilotArgs.Add($sessionId)
}

if ($dryRun) {
    Write-Output "# profile: $profileName   conf: $conf"
    Write-Output 'copilot'
    $copilotArgs | Write-Output
    exit 0
}

# Make cop's helper scripts (tf-check) callable by name in Copilot's shell.
$env:PATH = $PSScriptRoot + [System.IO.Path]::PathSeparator + $env:PATH

# Ctrl+C belongs to copilot; don't let it stop this script before the handoff check.
$treatCtrlC = [Console]::TreatControlCAsInput
try {
    if ($pinSession) { [Console]::TreatControlCAsInput = $true }
    & copilot @copilotArgs
    $code = $LASTEXITCODE
} finally {
    if ($pinSession) { [Console]::TreatControlCAsInput = $treatCtrlC }
}

if ($offerHandoff) {
    $status = Get-NotesStatus
    if ($status.Stale) {
        $answer = Read-Host "cop: NOTES.md is out of date ($($status.Reason)). Run the handoff skill now? [Y/n]"
        if ($answer -notmatch '^\s*(n|no)\s*$') {
            $modelArgs = Get-ModelArgs $handoffModel
            & copilot @permissionArgs @modelArgs --resume $sessionId -p 'Run the handoff skill to update NOTES.md for this session. Do nothing else.'
        }
    }
}
if ($pinSession -and $profileName -eq 'research') {
    [Console]::Error.WriteLine("cop: to continue this session with work permissions (findings carry over): cop work --resume $sessionId")
}
exit $code
