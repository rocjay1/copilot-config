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
# A throwaway COPILOT_HOME, so cop's reminder files never touch your real one.
$testHome = Join-Path ([System.IO.Path]::GetTempPath()) "cop-home-$([System.IO.Path]::GetRandomFileName())"
# cop runs in a throwaway git repo by default: work only starts inside one, and never in a
# folder that contains cop.psd1 (this checkout holds the fixture).
$workRepo = Join-Path ([System.IO.Path]::GetTempPath()) "cop-repo-$([System.IO.Path]::GetRandomFileName())"
New-Item -ItemType Directory -Path $workRepo | Out-Null
& git -C $workRepo init -q
$fail = 0; $total = 0

function Invoke-Cop([string[]]$CopArgs, [hashtable]$Env = @{}, [string]$Cwd = '') {
    $psi = [System.Diagnostics.ProcessStartInfo]::new($pwshExe)
    $psi.WorkingDirectory = if ($Cwd) { $Cwd } else { $workRepo }
    foreach ($a in @('-NoProfile', '-NonInteractive', '-File', $cop) + $CopArgs) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    # Redirected input, so cop never pins a session, whatever terminal runs the tests.
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Environment['COP_CONF'] = $fixture
    $psi.Environment['COPILOT_HOME'] = $testHome
    foreach ($k in $Env.Keys) { $psi.Environment[$k] = $Env[$k] }
    $p = [System.Diagnostics.Process]::Start($psi); $p.StandardInput.Close()
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

# Config keys
$keyConf = Join-Path ([System.IO.Path]::GetTempPath()) "cop-key-$([System.IO.Path]::GetRandomFileName()).psd1"
Set-Content $keyConf "@{ HandoffModel = 'session'; MaxAiCredits = 150 }"
$r = Invoke-Cop '--dry-run' -Env @{ COP_CONF = $keyConf }
Check 'accepts HandoffModel and MaxAiCredits keys' ($r.Code -eq 0 -and $r.Out -match "(?m)^150\r?$")
Remove-Item $keyConf

# Default model
$r = Invoke-Cop '--dry-run'
Check 'starts on Auto, balance tier' ($r.Out -match "(?m)^--model\r?\nauto\r?\n--auto-tier\r?\nbalance\r?$")
Check 'your own --model wins' (@([regex]::Matches((Invoke-Cop 'work', '--dry-run', '--model', 'gpt-x').Out, '--model')).Count -eq 1)
$mConf = Join-Path ([System.IO.Path]::GetTempPath()) "cop-model-$([System.IO.Path]::GetRandomFileName()).psd1"
Set-Content $mConf "@{ Model = '' }"
Check "Model = '' leaves the model to Copilot" ((Invoke-Cop '--dry-run' -Env @{ COP_CONF = $mConf }).Out -notmatch '--model')
Set-Content $mConf "@{ Model = 'claude-sonnet-5.5' }"
Check 'Model accepts a model id' ((Invoke-Cop '--dry-run' -Env @{ COP_CONF = $mConf }).Out -match "(?m)^--model\r?\nclaude-sonnet-5\.5\r?$")
Remove-Item $mConf

# AI credit cap
Check 'default cap of 100 credits' ((Invoke-Cop '--dry-run').Out -match "(?m)^--max-ai-credits\r?\n100\r?$")
Check 'your own --max-ai-credits wins' (@([regex]::Matches((Invoke-Cop 'work', '--dry-run', '--max-ai-credits', '40').Out, '--max-ai-credits')).Count -eq 1)
$capConf = Join-Path ([System.IO.Path]::GetTempPath()) "cop-cap-$([System.IO.Path]::GetRandomFileName()).psd1"
Set-Content $capConf "@{ MaxAiCredits = 0 }"
Check 'MaxAiCredits = 0 turns the cap off' ((Invoke-Cop '--dry-run' -Env @{ COP_CONF = $capConf }).Out -notmatch '--max-ai-credits')
Set-Content $capConf "@{ MaxAiCredits = 10 }"
Check 'rejects a cap below 30' ((Invoke-Cop '--dry-run' -Env @{ COP_CONF = $capConf }).Code -eq 2)
Remove-Item $capConf

# Session pin: cop pins only interactive sessions (both profiles), so with redirected input it
# never pins. Pinning itself needs a real terminal and is checked by hand, not here.
Check 'no session pin without a terminal' ((Invoke-Cop 'work', '--dry-run').Out -notmatch '--session-id')

# Where work may start: inside a git repo, never above COPILOT_HOME or cop.psd1
$plain = Join-Path ([System.IO.Path]::GetTempPath()) "cop-plain-$([System.IO.Path]::GetRandomFileName())"
New-Item -ItemType Directory -Path $plain | Out-Null
$r = Invoke-Cop '--dry-run' -Cwd $plain
Check 'work refuses to start outside a git repo' ($r.Code -eq 2 -and $r.Err -match 'outside a git repo')
Check 'research starts outside a git repo' ((Invoke-Cop 'research', '--dry-run' -Cwd $plain).Code -eq 0)
$r = Invoke-Cop 'work', '--dry-run', '--anywhere' -Cwd $plain
Check '--anywhere skips the check and is not passed on' ($r.Code -eq 0 -and $r.Out -notmatch '--anywhere')
& git -C $plain init -q
$plain = [System.IO.Path]::GetFullPath((& git -C $plain rev-parse --show-toplevel))   # real path (macOS temp is a symlink)
Check 'work starts in a git repo' ((Invoke-Cop '--dry-run' -Cwd $plain).Code -eq 0)
$r = Invoke-Cop '--dry-run' -Cwd $plain -Env @{ COPILOT_HOME = (Join-Path $plain '.copilot') }
Check 'work refuses a folder containing COPILOT_HOME' ($r.Code -eq 2 -and $r.Err -match 'pre-approved')
Copy-Item $fixture (Join-Path $plain 'cop.psd1')
$r = Invoke-Cop '--dry-run' -Cwd $plain -Env @{ COP_CONF = (Join-Path $plain 'cop.psd1') }
Check 'work refuses a folder containing cop.psd1' ($r.Code -eq 2 -and $r.Err -match 'pre-approved')
Remove-Item -Recurse -Force $plain

# Reminders (stderr, not in -p runs)
$stamp = Join-Path $testHome 'cop-friction-report.last'
Remove-Item -Force $stamp -ErrorAction SilentlyContinue
Check 'no stamp when -p' ((Invoke-Cop 'work', '--dry-run', '-p', 'x') -and -not (Test-Path $stamp))
$r = Invoke-Cop '--dry-run'
Check 'first run starts the report clock quietly' ((Test-Path $stamp) -and $r.Err -notmatch 'friction report')
(Get-Item $stamp).LastWriteTime = (Get-Date).AddDays(-8)
Check 'reminds after 7 days without a report' ((Invoke-Cop '--dry-run').Err -match 'friction report last ran 8 days ago')
Check 'no report reminder in -p runs' ((Invoke-Cop 'work', '--dry-run', '-p', 'x').Err -notmatch 'friction report')
(Get-Item $stamp).LastWriteTime = (Get-Date).AddDays(-2)
Check 'no report reminder within the week' ((Invoke-Cop '--dry-run').Err -notmatch 'friction report')

# Safety-test version check, against a fake copilot that reports 1.0.98.
$fakeBin = Join-Path $testHome 'bin'
New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
$fake = "#!/usr/bin/env pwsh`nWrite-Output 'GitHub Copilot CLI 1.0.98.'`n"
Set-Content (Join-Path $fakeBin 'copilot.ps1') $fake
if (-not $IsWindows) { Set-Content (Join-Path $fakeBin 'copilot') $fake; & chmod 755 (Join-Path $fakeBin 'copilot') }
$fakePath = @{ PATH = $fakeBin + [System.IO.Path]::PathSeparator + $env:PATH }
$testsStamp = Join-Path $testHome 'cop-safety-tests.passed'
Check 'warns when the safety tests never passed here' ((Invoke-Cop '--dry-run' -Env $fakePath).Err -match 'no record of the safety tests')
Set-Content $testsStamp '1.0.97'
Check 'warns when Copilot changed since the tests passed' ((Invoke-Cop '--dry-run' -Env $fakePath).Err -match 'Copilot CLI is 1\.0\.98, but the safety tests last passed on 1\.0\.97')
Check 'no version warning in -p runs' ((Invoke-Cop 'work', '--dry-run', '-p', 'x' -Env $fakePath).Err -notmatch 'safety tests')
Set-Content $testsStamp '1.0.98'
Check 'quiet when the tested version is installed' ((Invoke-Cop '--dry-run' -Env $fakePath).Err -notmatch 'safety tests')

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

Remove-Item -Recurse -Force $testHome, $workRepo -ErrorAction SilentlyContinue
Write-Output ''
Write-Output "cop cases: $($total - $fail)/$total passed"
exit ($fail -gt 0 ? 1 : 0)
