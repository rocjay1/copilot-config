#!/usr/bin/env pwsh
<#
.SYNOPSIS
Run Copilot CLI with a saved permission profile. PowerShell 7+, Windows/macOS/Linux.

.DESCRIPTION
  cop [work|research] [--dry-run] [copilot args...]

cop is `copilot` plus saved flags. It adds no behavior of its own: --resume, the session
picker, /exit, and everything else work exactly as in copilot.

  work      (default) The reads below and file edits under the starting folder run without
            prompting. Edits to <COPILOT_HOME> and cop.psd1 are denied wherever you start.
            Everything else prompts: pushes, PRs, ticket changes, unlisted commands.
  research  Same reads. File edits and the listed external writes are denied outright;
            any other shell command still prompts, so read what you approve.

A resumed session goes back to its own folder, and the edit approval follows it there.

Site-specific tools (MCP servers, your own CLIs) come from cop.psd1: $env:COP_CONF if set,
otherwise <COPILOT_HOME or ~/.copilot>/cop.psd1. Start from templates/cop.psd1.example.

Defaults, each skipped when you pass the flag yourself:
  --model auto --auto-tier balance   Model in cop.psd1 changes it; /model switches mid-session.
  --max-ai-credits 100               MaxAiCredits in cop.psd1 changes it (0 = off); /limits
                                     raises it mid-session.

--dry-run prints the copilot command this would run, one argument per line, and exits.

Every other argument passes through to copilot. PowerShell splits an argument that starts
with - and contains a colon (-name:value syntax), so put rules like shell(git:*) in cop.psd1
rather than on the command line.
#>

$ErrorActionPreference = 'Stop'

function Stop-Cop([string]$msg) { [Console]::Error.WriteLine("cop: $msg"); exit 2 }

$rest = [System.Collections.Generic.List[string]]::new()
foreach ($a in $args) { $rest.Add([string]$a) }

# The profile is an optional first word. Any other bare word there is an error, so a typo
# can't silently fall back to work.
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
foreach ($a in $rest) {
    if ($a -in 'work', 'research') { Stop-Cop "the profile must be the first argument (got '$a' later on)" }
}
$dryRun = $rest.Contains('--dry-run')
$passthru = @($rest | Where-Object { $_ -ne '--dry-run' })


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

# Model every cop session starts on: 'auto-balance' (Auto, balance tier), 'auto-efficiency',
# 'auto-intelligence', a model id, or '' to use Copilot's own saved setting. /model still changes
# it mid-session. Set Model in cop.psd1 to change it.
$model = 'auto-balance'

$cwd = (Get-Location).ProviderPath
$copilotHome = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.copilot' }
if ($env:COP_CONF) {
    if (-not (Test-Path -LiteralPath $env:COP_CONF -PathType Leaf)) { Stop-Cop "COP_CONF=$env:COP_CONF not found" }
    $conf = $env:COP_CONF
} else {
    $conf = Join-Path $copilotHome 'cop.psd1'
}

if (Test-Path -LiteralPath $conf -PathType Leaf) {
    # A data file: Import-PowerShellDataFile evaluates no code.
    $data = Import-PowerShellDataFile -LiteralPath $conf
    foreach ($key in $data.Keys) {
        if ($key -eq 'HandoffModel') { [Console]::Error.WriteLine("cop: ignoring HandoffModel in $conf (no longer used; delete it)"); continue }
        if ($key -notin 'ReadTools', 'ResearchDeny', 'MaxAiCredits', 'Model') { Stop-Cop "unknown key '$key' in $conf (expected ReadTools, ResearchDeny, MaxAiCredits, Model)" }
    }
    if ($data.Contains('Model')) { $model = [string]$data.Model }
    if ($data.Contains('MaxAiCredits')) { $maxAiCredits = [int]$data.MaxAiCredits }
    foreach ($t in @($data.ReadTools)) { if ($t) { $readTools.Add([string]$t) } }
    foreach ($t in @($data.ResearchDeny)) { if ($t) { $researchDeny.Add([string]$t) } }
} else {
    [Console]::Error.WriteLine("cop: no $conf; MCP and custom CLI reads will prompt (see templates/cop.psd1.example)")
}

# Work approves edits under the starting folder, which may contain Copilot's own config (e.g.
# when started in your home folder). Deny edits to it by absolute path; deny beats allow. A
# relative path resolves against PowerShell's location, not .NET's current directory.
$homeFull = [IO.Path]::GetFullPath($copilotHome, $cwd).TrimEnd('\', '/')
$confFull = [IO.Path]::GetFullPath($conf, $cwd)
$workDeny = @("write($homeFull/**)", "write($confFull)")

$copilotArgs = [System.Collections.Generic.List[string]]::new()
foreach ($t in $readTools) { $copilotArgs.Add("--allow-tool=$t") }
if ($profileName -eq 'research') {
    foreach ($t in $researchDeny) { $copilotArgs.Add("--deny-tool=$t") }
} else {
    foreach ($t in $workAllow) { $copilotArgs.Add("--allow-tool=$t") }
    foreach ($t in $workDeny) { $copilotArgs.Add("--deny-tool=$t") }
}
$ownLimit = @($passthru | Where-Object { $_ -match '^--max-ai-credits(=.*)?$' }).Count -gt 0
if ($maxAiCredits -gt 0 -and -not $ownLimit) {
    if ($maxAiCredits -lt 30) { Stop-Cop "MaxAiCredits must be 0 (off) or at least 30, Copilot's minimum (got $maxAiCredits)" }
    $copilotArgs.Add('--max-ai-credits'); $copilotArgs.Add("$maxAiCredits")
}
$ownModel = @($passthru | Where-Object { $_ -match '^--(model|auto-tier)(=.*)?$' }).Count -gt 0
if ($model -and -not $ownModel) {
    if ($model -match '^auto-(\w+)$') { $copilotArgs.AddRange([string[]]@('--model', 'auto', '--auto-tier', $Matches[1])) }
    else { $copilotArgs.AddRange([string[]]@('--model', $model)) }
}
$copilotArgs.AddRange([string[]]$passthru)

if ($dryRun) {
    Write-Output "# profile: $profileName   conf: $conf"
    Write-Output 'copilot'
    $copilotArgs | Write-Output
    exit 0
}

# Make cop's helper scripts (tf-check) callable by name in Copilot's shell.
$env:PATH = $PSScriptRoot + [System.IO.Path]::PathSeparator + $env:PATH

& copilot @copilotArgs
exit $LASTEXITCODE
