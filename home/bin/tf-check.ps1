#!/usr/bin/env pwsh
<#
.SYNOPSIS
Read-only Terraform checks that cop pre-approves as shell(tf-check). PowerShell 7+.

.DESCRIPTION
  tf-check [-chdir=DIR] fmt [args]        terraform fmt -check (never rewrites files)
  tf-check [-chdir=DIR] validate [args]   terraform validate
  tf-check version                        terraform version
  tf-check [-chdir=DIR] providers         terraform providers (lists requirements only)

Anything else is refused, so it can't be used to change state or infrastructure. plan, init,
and test (whose run blocks can apply real infrastructure unless the providers are mocked) go
through `terraform` itself and keep prompting.
#>

$rest = [System.Collections.Generic.List[string]]::new()
foreach ($a in $args) { $rest.Add([string]$a) }

function Stop-Check([string]$msg) { [Console]::Error.WriteLine("tf-check: $msg"); exit 2 }

$global = @()
if ($rest.Count -gt 0 -and $rest[0] -like '-chdir=*') { $global = @($rest[0]); $rest.RemoveAt(0) }
if ($rest.Count -eq 0) { Stop-Check 'usage: tf-check [-chdir=DIR] fmt|validate|version|providers [args]' }
$sub = $rest[0]; $rest.RemoveAt(0)

switch ($sub) {
    'fmt' {
        if (@($rest | Where-Object { $_ -match '^-+write' }).Count) { Stop-Check 'fmt always runs with -check; -write is not allowed' }
        & terraform @global fmt -check @rest
    }
    'validate' { & terraform @global validate @rest }
    'version' { & terraform version @rest }
    'providers' {
        if ($rest.Count -and -not $rest[0].StartsWith('-')) { Stop-Check "'providers $($rest[0])' is not allowed (it can write files); only bare 'providers'" }
        & terraform @global providers @rest
    }
    default { Stop-Check "'$sub' is not a read-only check; run terraform $sub directly (it will prompt)" }
}
exit $LASTEXITCODE
