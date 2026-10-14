#!/usr/bin/env pwsh
<#
Offline test for the cop launcher (home/bin/cop.ps1). Uses --dry-run, so no Copilot session
and no premium requests.

  tests/cop.ps1
#>

$R = Split-Path -Parent $PSScriptRoot
$cop = Join-Path $R 'home/bin/cop.ps1'
$pwshExe = (Get-Process -Id $PID).Path
$fixture = Join-Path $R 'tests/fixtures/cop.psd1'
$fail = 0; $total = 0

function Invoke-Cop([string[]]$CopArgs, [hashtable]$Env = @{}, [string]$Cwd = '') {
    $psi = [System.Diagnostics.ProcessStartInfo]::new($pwshExe)
    if ($Cwd) { $psi.WorkingDirectory = $Cwd }
    foreach ($a in @('-NoProfile', '-NonInteractive', '-File', $cop) + $CopArgs) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Environment['COP_CONF'] = $fixture
    foreach ($k in $Env.Keys) { $psi.Environment[$k] = $Env[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd(); $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{ Code = $p.ExitCode; Out = $out; Err = $err }
}

function Check([string]$label, [bool]$ok) {
    $script:total++
    if (-not $ok) { $script:fail++; Write-Output "FAIL  $label" }
}

# Profiles
$r = Invoke-Cop '--dry-run'
Check 'default profile is work' ($r.Code -eq 0 -and $r.Out -match '# profile: work' -and $r.Out -notmatch '--deny-tool')
Check 'work pre-approves file edits' ($r.Out -match '(?m)^--allow-tool=write\r?$')
$r = Invoke-Cop 'research', '--dry-run'
Check 'research adds deny rules' ($r.Code -eq 0 -and $r.Out -match '# profile: research' -and $r.Out -match '--deny-tool=write' -and $r.Out -match '--deny-tool=shell\(git push\)')
Check 'research does not pre-approve file edits' ($r.Out -notmatch '(?m)^--allow-tool=write\r?$')
Check 'research includes conf denies' ($r.Out -match [regex]::Escape('--deny-tool=fakejira(createIssue)'))
Check 'conf reads are allowed' ($r.Out -match [regex]::Escape('--allow-tool=fakejira(getIssue)'))
Check 'passthrough keeps -p and its value' ((Invoke-Cop 'work', '--dry-run', '-p', 'hello world').Out -match "(?m)^-p\r?\n^hello world")

foreach ($bad in @('reserach'), @('--dry-run', 'research'), @('-p', 'x', 'work'), @('help')) {
    $r = Invoke-Cop $bad
    Check "rejects profile misuse: $($bad -join ' ')" ($r.Code -eq 2)
}

# Refused flags
foreach ($flag in @('--yolo'), @('--yolo=true'), @('--allow-all'), @('--allow-all=true'), @('--allow-all-tools'),
    @('--allow-all-paths'), @('--allow-all-urls'), @('--autopilot'), @('--assisted-approval'),
    @('--mode=autopilot'), @('--mode', 'autopilot')) {
    $r = Invoke-Cop (@('work', '--dry-run') + $flag)
    Check "refuses $($flag -join ' ')" ($r.Code -eq 2 -and $r.Err -match 'refusing')
}
Check 'allows --mode plan' ((Invoke-Cop 'work', '--dry-run', '--mode', 'plan').Code -eq 0)

# Environment variables that pre-approve everything are cleared, with a warning
foreach ($var in 'COPILOT_ALLOW_ALL', 'COPILOT_ASSISTED_APPROVAL') {
    $r = Invoke-Cop '--dry-run' -Env @{ $var = 'true' }
    Check "clears $var" ($r.Code -eq 0 -and $r.Err -match "ignoring $var")
}

# Bad config
$badConf = Join-Path ([System.IO.Path]::GetTempPath()) "cop-test-$([System.IO.Path]::GetRandomFileName()).psd1"
Set-Content $badConf "@{ ReadTool = @('x') }"
$r = Invoke-Cop '--dry-run' -Env @{ COP_CONF = $badConf }
Check 'rejects unknown config key' ($r.Code -eq 2 -and $r.Err -match 'unknown key')
Remove-Item $badConf
$r = Invoke-Cop '--dry-run' -Env @{ COP_CONF = '/nonexistent/cop.psd1' }
Check 'rejects missing COP_CONF' ($r.Code -eq 2)


# Helpers and reads added from friction-report evidence
$r = Invoke-Cop 'research', '--dry-run'
Check 'tf-check, printf, echo pre-approved' ($r.Out -match [regex]::Escape('--allow-tool=shell(tf-check)') -and $r.Out -match [regex]::Escape('--allow-tool=shell(printf)') -and $r.Out -match [regex]::Escape('--allow-tool=shell(echo)'))
Check 'gh deny rules use the prefix form' ($r.Out -match [regex]::Escape('--deny-tool=shell(gh pr create:*)') -and $r.Out -notmatch [regex]::Escape('--deny-tool=shell(gh pr create)'))

# AI credit cap
Check 'default cap of 100 credits' ((Invoke-Cop '--dry-run').Out -match "(?m)^--max-ai-credits\r?\n100\r?$")
Check 'your own --max-ai-credits wins' (@([regex]::Matches((Invoke-Cop 'work', '--dry-run', '--max-ai-credits', '40').Out, '--max-ai-credits')).Count -eq 1)
$capConf = Join-Path ([System.IO.Path]::GetTempPath()) "cop-cap-$([System.IO.Path]::GetRandomFileName()).psd1"
Set-Content $capConf "@{ MaxAiCredits = 0 }"
Check 'MaxAiCredits = 0 turns the cap off' ((Invoke-Cop '--dry-run' -Env @{ COP_CONF = $capConf }).Out -notmatch '--max-ai-credits')
Set-Content $capConf "@{ MaxAiCredits = 10 }"
Check 'rejects a cap below 30' ((Invoke-Cop '--dry-run' -Env @{ COP_CONF = $capConf }).Code -eq 2)
Remove-Item $capConf

# Handoff on exit: never in -p runs or research
Check 'no session pin for -p runs' ((Invoke-Cop 'work', '--dry-run', '-p', 'x').Out -notmatch '--session-id')
Check 'no session pin in research' ((Invoke-Cop 'research', '--dry-run').Out -notmatch '--session-id')

# --check-notes: NOTES.md staleness against the handoff State fingerprint
$repo = Join-Path ([System.IO.Path]::GetTempPath()) "cop-notes-$([System.IO.Path]::GetRandomFileName())"
New-Item -ItemType Directory -Path $repo | Out-Null
function Notes([string]$label, [int]$want) { $r = Invoke-Cop '--check-notes' -Cwd $repo; Check "check-notes: $label ($($r.Out.Trim()))" ($r.Code -eq $want) }
Notes 'not a git repo is current' 0
& git -C $repo init -q; Set-Content (Join-Path $repo a.tf) 'a'
& git -C $repo add a.tf; & git -C $repo -c user.name=t -c user.email=t@example.invalid commit -qm i
Notes 'clean repo is current' 0
Set-Content (Join-Path $repo b.tf) 'b'; Add-Content (Join-Path $repo a.tf) 'more'
Notes 'changes without NOTES.md are stale' 1
Set-Content (Join-Path $repo NOTES.md) "## Goal`n- test`n"
Notes 'NOTES.md without State is stale' 1
$h = @(& git -C $repo hash-object -- a.tf b.tf)
Set-Content (Join-Path $repo NOTES.md) "## Goal`n- test`n`n## State`n- ``a.tf`` $($h[0].Substring(0,7))`n- ``b.tf`` $($h[1].Substring(0,7))`n"
Notes 'matching fingerprint is current' 0
Add-Content (Join-Path $repo b.tf) 'drift'
Notes 'edit after handoff is stale' 1
& git -C $repo add a.tf b.tf; & git -C $repo -c user.name=t -c user.email=t@example.invalid commit -qm work
$head = (& git -C $repo rev-parse --short=7 HEAD)
Set-Content (Join-Path $repo NOTES.md) "## Goal`n- test`n`n## State`n- HEAD $head`n"
Notes 'clean tree at the recorded HEAD is current' 0
Set-Content (Join-Path $repo c.tf) 'c'
& git -C $repo add c.tf; & git -C $repo -c user.name=t -c user.email=t@example.invalid commit -qm more
Notes 'new commit after handoff is stale' 1
Set-Content (Join-Path $repo NOTES.md) "## Goal`n- test`n`n## State`n- clean at $(& git -C $repo rev-parse --short=7 HEAD)`n"
Notes 'older clean-at format at HEAD is current' 0
Remove-Item -Recurse -Force $repo

Write-Output ''
Write-Output "cop cases: $($total - $fail)/$total passed"
exit ($fail -gt 0 ? 1 : 0)
