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
# A throwaway COPILOT_HOME and starting folder; cop only reads them.
$testHome = Join-Path ([System.IO.Path]::GetTempPath()) "cop-home-$([System.IO.Path]::GetRandomFileName())"
$workDir = Join-Path ([System.IO.Path]::GetTempPath()) "cop-cwd-$([System.IO.Path]::GetRandomFileName())"
New-Item -ItemType Directory -Path $workDir | Out-Null
$fail = 0; $total = 0

function Invoke-Cop([string[]]$CopArgs, [hashtable]$Env = @{}, [string]$Cwd = '') {
    $psi = [System.Diagnostics.ProcessStartInfo]::new($pwshExe)
    $psi.WorkingDirectory = if ($Cwd) { $Cwd } else { $workDir }
    foreach ($a in @('-NoProfile', '-NonInteractive', '-File', $cop) + $CopArgs) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
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
Check 'default profile is work' ($r.Code -eq 0 -and $r.Out -match '# profile: work')
Check 'work denies only its own config and code-running folders' (@($r.Out -split '\r?\n' | Where-Object { $_ -like '--deny-tool=*' }).Count -eq 5)
Check 'work pre-approves file edits' ($r.Out -match '(?m)^--allow-tool=write\r?$')
$r = Invoke-Cop 'research', '--dry-run'
Check 'research adds deny rules' ($r.Code -eq 0 -and $r.Out -match '# profile: research' -and $r.Out -match '--deny-tool=write' -and $r.Out -match '--deny-tool=shell\(git push\)')
Check 'research does not pre-approve file edits' ($r.Out -notmatch '(?m)^--allow-tool=write\r?$')
Check 'research includes conf denies' ($r.Out -match [regex]::Escape('--deny-tool=fakejira(createIssue)'))
Check 'conf reads are allowed' ($r.Out -match [regex]::Escape('--allow-tool=fakejira(getIssue)'))
Check 'passthrough keeps -p and its value' ((Invoke-Cop 'work', '--dry-run', '-p', 'hello world').Out -match "(?m)^-p\r?\n^hello world")

foreach ($bad in @('reserach'), @('help')) {
    $r = Invoke-Cop $bad
    Check "rejects profile misuse: $($bad -join ' ')" ($r.Code -eq 2)
}
# Only the first argument picks the profile; later, work and research are plain words.
$r = Invoke-Cop '--dry-run', '-p', 'work'
Check 'a prompt of "work" passes through' ($r.Code -eq 0 -and $r.Out -match '# profile: work' -and $r.Out -match "(?m)^-p\r?\nwork\r?$")

# Everything else passes through to copilot unchanged: cop adds flags, never behavior.
foreach ($flag in @('--resume'), @('--resume', 'abc-123'), @('--continue'), @('--yolo'), @('--mode', 'autopilot')) {
    $r = Invoke-Cop (@('work', '--dry-run') + $flag)
    Check "passes through $($flag -join ' ')" ($r.Code -eq 0 -and $r.Out -match ("(?m)^" + [regex]::Escape($flag[-1]) + "\r?$"))
}
foreach ($removed in '--anywhere', '--check-notes') {
    Check "no special meaning for $removed" ((Invoke-Cop 'work', '--dry-run', $removed).Out -match ("(?m)^" + $removed + "\r?$"))
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
Check 'accepts MaxAiCredits; ignores the old HandoffModel key with a notice' ($r.Code -eq 0 -and $r.Out -match "(?m)^150\r?$" -and $r.Err -match 'ignoring HandoffModel')
Remove-Item $keyConf

# Model: left to Copilot's own settings
$r = Invoke-Cop '--dry-run'
Check 'adds no --model or --auto-tier' ($r.Out -notmatch '(?m)^--(model|auto-tier)')
$r = Invoke-Cop 'work', '--dry-run', '--model', 'gpt-x'
Check 'your own --model passes through' (@([regex]::Matches($r.Out, '(?m)^--model\r?$')).Count -eq 1 -and $r.Out -match "(?m)^--model\r?\ngpt-x\r?$")
$mConf = Join-Path ([System.IO.Path]::GetTempPath()) "cop-model-$([System.IO.Path]::GetRandomFileName()).psd1"
Set-Content $mConf "@{ Model = 'auto-balance' }"
$r = Invoke-Cop '--dry-run' -Env @{ COP_CONF = $mConf }
Check 'ignores the old Model key with a notice' ($r.Code -eq 0 -and $r.Err -match 'ignoring Model' -and $r.Out -notmatch '(?m)^--model')
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

# Work denies edits to Copilot's own config, by absolute path, wherever it starts
$r = Invoke-Cop '--dry-run'
$homeRule = '--deny-tool=write(' + [System.IO.Path]::GetFullPath($testHome).TrimEnd('\', '/') + '/**)'
Check 'work denies edits under COPILOT_HOME' ($r.Out -match ('(?m)^' + [regex]::Escape($homeRule) + '\r?$'))
Check 'work denies edits to cop.psd1' ($r.Out -match ('(?m)^' + [regex]::Escape("--deny-tool=write($fixture)") + '\r?$'))
$r = Invoke-Cop '--dry-run' -Env @{ COPILOT_HOME = 'sub/.copilot' }
$rule = @($r.Out -split '\r?\n' | Where-Object { $_ -match '^--deny-tool=write\(.*[\\/]\.copilot/\*\*\)$' })
Check 'a relative COPILOT_HOME becomes an absolute rule' ($rule.Count -eq 1 -and $rule[0] -match '^--deny-tool=write\((/|[A-Za-z]:\\).*[\\/]sub[\\/]\.copilot/\*\*\)$')
Check 'the hook gets the same resolved paths' ($r.Out -match ('(?m)COPILOT_HOME: (/|[A-Za-z]:\\).*[\\/]sub[\\/]\.copilot\r?$'))
# The launched copilot (a fake that prints its environment) gets the resolved paths
$fakeBin = Join-Path $testHome 'fakebin'
New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
$fake = "#!/usr/bin/env pwsh`nWrite-Output `"env: `$env:COPILOT_HOME|`$env:COP_CONF`"`n"
Set-Content (Join-Path $fakeBin 'copilot.ps1') $fake
if (-not $IsWindows) { Set-Content (Join-Path $fakeBin 'copilot') $fake; & chmod 755 (Join-Path $fakeBin 'copilot') }
$r = Invoke-Cop @() -Env @{ COPILOT_HOME = 'sub/.copilot'; PATH = $fakeBin + [System.IO.Path]::PathSeparator + $env:PATH }
Check 'copilot runs with an absolute COPILOT_HOME and COP_CONF' ($r.Out -match ('env: (/|[A-Za-z]:\\).*[\\/]sub[\\/]\.copilot\|' + [regex]::Escape($fixture)))
$r = Invoke-Cop '--dry-run'
# ...and edits that would make a pre-approved read run code
foreach ($t in 'write(.git)', 'write(.git/**)', 'write(.terraform/**)') {
    Check "work denies $t" ($r.Out -match ('(?m)^' + [regex]::Escape("--deny-tool=$t") + '\r?$'))
}
# Git won't load config from a folder that only looks like a bare repo; added after the caller's settings
Check 'git treats only explicit bare repos as repos' ((Invoke-Cop '--dry-run').Out -match '(?m)^# env: GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe\.bareRepository GIT_CONFIG_VALUE_0=explicit\r?$')
Check 'the git setting follows existing ones' ((Invoke-Cop '--dry-run' -Env @{ GIT_CONFIG_COUNT = '2' }).Out -match '(?m)^# env: GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_2=safe\.bareRepository GIT_CONFIG_VALUE_2=explicit\r?$')
Check 'research adds no path denies (it denies all edits)' ((Invoke-Cop 'research', '--dry-run').Out -notmatch '--deny-tool=write\(')

Remove-Item -Recurse -Force $testHome, $workDir -ErrorAction SilentlyContinue
Write-Output ''
Write-Output "cop cases: $($total - $fail)/$total passed"
exit ($fail -gt 0 ? 1 : 0)
