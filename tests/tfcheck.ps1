#!/usr/bin/env pwsh
<#
Offline test for home/bin/tf-check.ps1: it must refuse anything that could change files, state,
or infrastructure. Runs terraform only for `version`, and skips that if terraform isn't installed.

  tests/tfcheck.ps1
#>

$R = Split-Path -Parent $PSScriptRoot
$tf = Join-Path $R 'home/bin/tf-check.ps1'
$pwshExe = (Get-Process -Id $PID).Path
$fail = 0; $total = 0
function Check([string]$label, [bool]$ok) { $script:total++; if (-not $ok) { $script:fail++; Write-Output "FAIL  $label" } }
function Invoke-Tf([string[]]$TfArgs) {
    $out = & $pwshExe -NoProfile -NonInteractive -File $tf @TfArgs 2>&1
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($out -join "`n") }
}

foreach ($refused in @('apply'), @('destroy'), @('plan'), @('init'), @('test'), @('import', 'a', 'b'),
    @('state', 'rm', 'x'), @('-chdir=infra', 'apply'), @('fmt', '-write=true'), @('fmt', '--write'),
    @('providers', 'lock'), @('providers', 'mirror', 'dir'), @()) {
    $r = Invoke-Tf $refused
    Check "refuses: tf-check $($refused -join ' ')" ($r.Code -eq 2 -and $r.Out -match 'tf-check:')
}

if (Get-Command terraform -ErrorAction SilentlyContinue) {
    $r = Invoke-Tf @('version')
    Check 'runs: tf-check version' ($r.Code -eq 0 -and $r.Out -match 'Terraform v')
} else {
    Write-Output 'skip  tf-check version (terraform not installed)'
}

Write-Output "tf-check cases: $($total - $fail)/$total passed"
exit ($fail -gt 0 ? 1 : 0)
