#!/usr/bin/env pwsh
<#
Offline test for scripts/friction-report.ps1. Builds a fake COPILOT_HOME with one session log
and a friction log, then checks the report's counts, and that no arguments, paths, branch
names, or other planted secrets appear in it.

  tests/report.ps1
#>

$R = Split-Path -Parent $PSScriptRoot
$report = Join-Path $R 'scripts/friction-report.ps1'
$fail = 0; $total = 0
function Check([string]$label, [bool]$ok) { $script:total++; if (-not $ok) { $script:fail++; Write-Output "FAIL  $label" } }

$home_ = Join-Path ([System.IO.Path]::GetTempPath()) "cop-report-$([System.IO.Path]::GetRandomFileName())"
$sessionDir = Join-Path $home_ 'session-state/11111111-1111-1111-1111-111111111111'
New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null

$now = (Get-Date).ToUniversalTime().ToString('o')
function Ev([string]$type, $data) { [ordered]@{ type = $type; timestamp = $now; data = $data } | ConvertTo-Json -Depth 20 -Compress }
$events = @(
    Ev 'session.start' @{ copilotVersion = '1.0.97'; startTime = $now; context = @{ cwd = '/SECRET-PATH/repo'; branch = 'SECRET-BRANCH' } }
    # A prompt you approved: cat was allowed by a rule, printf wasn't.
    Ev 'permission.requested' @{ requestId = 'r1'; permissionRequest = @{ kind = 'shell'; fullCommandText = 'cat SECRET-FILE | printf SECRET-ARG'; commands = @(
        @{ identifier = 'cat'; readOnly = $true; allowMatchIdentifier = 'cat' }, @{ identifier = 'printf'; readOnly = $false; allowMatchIdentifier = $null }) } }
    Ev 'permission.completed' @{ requestId = 'r1'; result = @{ kind = 'approved' }; decisionSource = 'human_response' }
    # A second prompt, for a read-only command, that you denied.
    Ev 'permission.requested' @{ requestId = 'r2'; permissionRequest = @{ kind = 'shell'; fullCommandText = 'git ls-files SECRET-DIR'; commands = @(
        @{ identifier = 'git ls-files'; readOnly = $true; allowMatchIdentifier = $null }) } }
    Ev 'permission.completed' @{ requestId = 'r2'; result = @{ kind = 'denied-interactively-by-user' }; decisionSource = 'human_response' }
    # Approved by a rule: not a prompt, must not be counted.
    Ev 'permission.requested' @{ requestId = 'r3'; permissionRequest = @{ kind = 'shell'; commands = @(@{ identifier = 'git status'; readOnly = $true; allowMatchIdentifier = 'git status' }) } }
    Ev 'permission.completed' @{ requestId = 'r3'; result = @{ kind = 'approved' }; decisionSource = $null }
    # An MCP prompt.
    Ev 'permission.requested' @{ requestId = 'r4'; permissionRequest = @{ kind = 'mcp'; serverName = 'atlassian'; toolName = 'atlassian-createJiraIssue'; args = @{ summary = 'SECRET-SUMMARY' } } }
    Ev 'permission.completed' @{ requestId = 'r4'; result = @{ kind = 'approved' }; decisionSource = 'human_response' }
    # Denials: a deny rule and the guardrail hook.
    Ev 'tool.execution_complete' @{ success = $false; error = @{ message = 'Permission to run this tool was denied due to the following rules: `shell(git push)`' } }
    Ev 'tool.execution_complete' @{ success = $false; error = @{ message = 'Denied by preToolUse hook: Blocked by guardrail hook (kubectl -n SECRET-NAMESPACE delete). Infrastructure changes...' } }
    Ev 'skill.invoked' @{ name = 'work-ticket'; content = 'SECRET-SKILL-BODY' }
    Ev 'session.shutdown' @{ accountingSnapshot = @{ totalNanoAiu = 4200000000.0 } }
)
Set-Content (Join-Path $sessionDir 'events.jsonl') $events

$today = (Get-Date).ToString('yyyy-MM-dd')
Set-Content (Join-Path $home_ 'friction-log.md') @(
    "- $today [batching] batch was 5 files despite the 3-file rule"
    '- 2020-01-01 [prompts] old entry outside the window'
)

$out = (& (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $report -Days 7 -CopilotHome $home_) -join "`n"

Check 'counts the session and version' ($out -match 'Sessions: 1\. Copilot versions: 1\.0\.97\.')
Check 'reports credits' ($out -match 'AI credits: 4\.2 total')
Check 'counts the printf prompt' ($out -match '\| shell: printf \| 1 \|')
Check 'lists unapproved commands one by one' ($out -match '\| `printf` \| 1 \|' -and $out -match '\| `git ls-files` \(read-only\) \| 1 \|')
Check 'does not list rule-approved commands' ($out -notmatch '`cat`' -and $out -notmatch 'git status')
Check 'counts the MCP prompt' ($out -match '\| mcp: atlassian\(createJiraIssue\) \| 1 \|')
Check 'counts your answers' ($out -match 'approved 2' -and $out -match 'denied-interactively-by-user 1')
Check 'counts the deny rule' ($out -match '\| shell\(git push\) \| 1 \|')
Check 'labels the hook block with tool and verb only' ($out -match '\| kubectl delete \| 1 \|')
Check 'counts the skill' ($out -match '\| work-ticket \| 1 \|')
Check 'includes recent friction entries only' ($out -match 'despite the 3-file rule' -and $out -notmatch 'old entry')
Check 'never prints planted secrets' ($out -notmatch 'SECRET')

Remove-Item -Recurse -Force $home_
Write-Output "report cases: $($total - $fail)/$total passed"
exit ($fail -gt 0 ? 1 : 0)
