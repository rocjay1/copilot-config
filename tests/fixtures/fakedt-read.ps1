#!/usr/bin/env pwsh
# Read-only shim for fakedt: passes read subcommands through and refuses the rest.
# Copilot can only approve a custom CLI as a whole (shell(fakedt)), not per subcommand, so
# approving shell(fakedt-read) is how reads get pre-approved without approving fakedt's writes.
switch ($args[0]) {
    'get' { & fakedt @args; exit $LASTEXITCODE }
    default { [Console]::Error.WriteLine("fakedt-read: only read subcommands are allowed (got: $($args[0]))"); exit 2 }
}
