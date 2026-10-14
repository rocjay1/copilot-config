#!/usr/bin/env pwsh
<#
Summarize how Copilot CLI sessions went, from Copilot's own local session logs. PowerShell 7+.

  scripts/friction-report.ps1 [-Days 7]

Reads <COPILOT_HOME or ~/.copilot>/session-state/*/events.jsonl and
<COPILOT_HOME>/friction-log.md (written by the friction-log skill), and prints a Markdown
report: what you were prompted for, what was blocked, which skills ran, and what it cost.

It reports command names, tool names, rule names, and counts only. It never prints command
arguments, paths, repo or branch names, or file contents. It's meant to be read on the
machine it runs on; nothing is sent anywhere. Its only write is <COPILOT_HOME>/cop-friction-report.last,
which records the run so cop can remind you when a week has passed without one.
#>
param(
    [int]$Days = 7,
    [string]$CopilotHome = $(if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.copilot' })
)

$since = (Get-Date).ToUniversalTime().AddDays(-$Days)
$stateDir = Join-Path $CopilotHome 'session-state'

function Add-Count([hashtable]$table, [string]$key) { if ($key) { $table[$key] = 1 + ($table[$key] ?? 0) } }
function Write-Table([hashtable]$table, [string]$header, [int]$top = 15) {
    if ($table.Count -eq 0) { Write-Output '(none)'; return }
    Write-Output "| $header | Count |"
    Write-Output '|---|---|'
    $table.GetEnumerator() | Sort-Object -Property @{ Expression = 'Value'; Descending = $true }, Name |
        Select-Object -First $top | ForEach-Object { Write-Output "| $($_.Name) | $($_.Value) |" }
}

# What a permission request was for, without arguments or paths.
function Get-RequestLabel($req) {
    switch ($req.kind) {
        'shell' {
            $ids = @($req.commands | Where-Object { -not $_.allowMatchIdentifier } | ForEach-Object { $_.identifier })
            if (-not $ids) { $ids = @($req.commands | ForEach-Object { $_.identifier }) }
            $label = ($ids | Select-Object -Unique) -join ' + '
            if ($req.hasWriteFileRedirection) { $label += ' (with > redirect)' }
            return "shell: $label"
        }
        'mcp' { return "mcp: $($req.serverName)($($req.toolName -replace "^$([regex]::Escape($req.serverName))-", ''))" }
        'write' { return 'file edit' }
        'read' { return 'file read outside the working folder' }
        'url' { return 'url access' }
        default { return [string]$req.kind }
    }
}

$sessions = 0; $versions = @{}
$prompted = @{}; $promptedCommands = @{}; $answers = @{}
$ruleDenied = @{}; $hookDenied = @{}; $unattended = @{}
$skills = @{}; $credits = [System.Collections.Generic.List[double]]::new()

$files = if (Test-Path $stateDir) { @(Get-ChildItem $stateDir -Filter events.jsonl -Recurse -File) } else { @() }
foreach ($file in $files) {
    $requests = @{}; $inRange = $false; $maxCredits = 0.0
    foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
        if (-not $line) { continue }
        try { $e = $line | ConvertFrom-Json -Depth 50 } catch { continue }
        switch ($e.type) {
            'session.start' {
                if ([datetime]$e.data.startTime -ge $since) { $inRange = $true; $sessions++; Add-Count $versions $e.data.copilotVersion }
            }
            'session.resume' { if ($e.timestamp -and [datetime]$e.timestamp -ge $since -and -not $inRange) { $inRange = $true; $sessions++ } }
            'permission.requested' { $requests[$e.data.requestId] = $e.data.permissionRequest }
            'permission.completed' {
                if (-not $inRange) { break }
                $req = $requests[$e.data.requestId]; if (-not $req) { break }
                $label = Get-RequestLabel $req
                $kind = $e.data.result.kind
                if ($e.data.decisionSource -eq 'human_response') {
                    Add-Count $prompted $label
                    Add-Count $answers $kind
                    if ($req.kind -eq 'shell') {
                        foreach ($c in @($req.commands | Where-Object { -not $_.allowMatchIdentifier })) {
                            Add-Count $promptedCommands ("``$($c.identifier)``" + $(if ($c.readOnly) { ' (read-only)' } else { '' }))
                        }
                    }
                } elseif ($kind -like 'denied-no-approval-rule*') {
                    Add-Count $unattended $label
                }
            }
            'tool.execution_complete' {
                if (-not $inRange -or $e.data.success) { break }
                $msg = [string]$e.data.error.message
                if ($msg -match 'following rules: `([^`]+)`') { Add-Count $ruleDenied $Matches[1] }
                elseif ($msg -match 'Blocked by guardrail hook \(([^)]*)\)') {
                    # Tool and verb only (first and last word), e.g. "kubectl delete" from
                    # "kubectl -n <namespace> delete", so names and arguments never show.
                    $words = @($Matches[1].Trim() -split '\s+' | Where-Object { $_ })
                    $verb = ($words[-1] -split '=')[0]
                    Add-Count $hookDenied ($(if ($words.Count -gt 1) { "$($words[0]) $verb" } else { $words[0] }))
                }
            }
            'skill.invoked' { if ($inRange) { Add-Count $skills $e.data.name } }
            { $_ -in 'session.shutdown', 'session.usage_checkpoint' } {
                $nano = $e.data.accountingSnapshot.totalNanoAiu ?? $e.data.totalNanoAiu
                if ($nano -and [double]$nano / 1e9 -gt $maxCredits) { $maxCredits = [double]$nano / 1e9 }
            }
        }
    }
    if ($inRange -and $maxCredits -gt 0) { $credits.Add($maxCredits) }
}

Write-Output "# Copilot friction report: last $Days days"
Write-Output ''
Write-Output "Sessions: $sessions. Copilot versions: $(if ($versions.Count) { ($versions.Keys | Sort-Object) -join ', ' } else { 'n/a' })."
if ($credits.Count) {
    $total = ($credits | Measure-Object -Sum).Sum
    Write-Output ("AI credits: {0:N1} total, {1:N1} per session on average, {2:N1} for the most expensive session." -f $total, ($total / $credits.Count), ($credits | Measure-Object -Maximum).Maximum)
}
Write-Output ''
Write-Output '## Prompts you answered'
Write-Table $prompted 'Prompted for'
Write-Output ''
Write-Output "Your answers: $(if ($answers.Count) { ($answers.GetEnumerator() | ForEach-Object { "$($_.Name) $($_.Value)" }) -join ', ' } else { 'none' })."
Write-Output ''
Write-Output '## Commands that needed your approval, one by one'
Write-Output 'Candidates for ReadTools in cop.psd1: only commands that never change anything, whatever'
Write-Output 'their arguments. "(read-only)" is Copilot''s own classification.'
Write-Output ''
Write-Table $promptedCommands 'Command'
Write-Output ''
Write-Output '## Denied by a cop deny rule'
Write-Table $ruleDenied 'Rule'
Write-Output ''
Write-Output '## Blocked by the guardrail hook'
Write-Table $hookDenied 'Command'
Write-Output ''
Write-Output '## Refused in -p runs (no one to ask)'
Write-Table $unattended 'Request'
Write-Output ''
Write-Output '## Skills used'
Write-Table $skills 'Skill'

$log = Join-Path $CopilotHome 'friction-log.md'
Write-Output ''
Write-Output '## Friction log'
if (Test-Path $log) {
    $entries = @(Get-Content $log | Where-Object { $_ -match '^- (\d{4}-\d{2}-\d{2}) \[([a-z-]+)\]' } |
        Where-Object { [datetime]($_.Substring(2, 10)) -ge $since.Date })
    $byCategory = @{}; foreach ($l in $entries) { if ($l -match '\[([a-z-]+)\]') { Add-Count $byCategory $Matches[1] } }
    Write-Table $byCategory 'Category'
    if ($entries) { Write-Output ''; $entries | ForEach-Object { Write-Output $_ } }
} else {
    Write-Output "(no $log yet; the friction-log skill creates it)"
}

# Record this run for cop's weekly reminder.
try { Set-Content -LiteralPath (Join-Path $CopilotHome 'cop-friction-report.last') -Value (Get-Date).ToString('o') -ErrorAction Stop } catch {}
