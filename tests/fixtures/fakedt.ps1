#!/usr/bin/env pwsh
# Stand-in for a site-specific CLI (e.g. a Dynatrace CLI) in the permission smoke test.
# `get` reads, `set` writes. Every invocation is appended to $env:FAKEDT_LOG, which is the
# ground truth for which commands actually ran.
if (-not $env:FAKEDT_LOG) { [Console]::Error.WriteLine('FAKEDT_LOG not set'); exit 2 }
Add-Content -LiteralPath $env:FAKEDT_LOG -Value ($args -join ' ')
$name = if ($args.Count -gt 1) { $args[1] } else { 'host' }
switch ($args[0]) {
    'get' { "${name}: cpu 12%, mem 40%" }
    'set' { "${name}: updated" }
    default { [Console]::Error.WriteLine('usage: fakedt get|set NAME'); exit 2 }
}
