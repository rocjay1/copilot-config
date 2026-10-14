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

function Invoke-Cop([string[]]$CopArgs, [hashtable]$Env = @{}) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new($pwshExe)
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
$r = Invoke-Cop 'research', '--dry-run'
Check 'research adds deny rules' ($r.Code -eq 0 -and $r.Out -match '# profile: research' -and $r.Out -match '--deny-tool=write' -and $r.Out -match '--deny-tool=shell\(git push\)')
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

Write-Output ''
Write-Output "cop cases: $($total - $fail)/$total passed"
exit ($fail -gt 0 ? 1 : 0)
