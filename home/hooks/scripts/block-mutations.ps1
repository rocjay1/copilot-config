<#
preToolUse guardrail: deny shell commands that mutate infrastructure. PowerShell 7+.

Reads the hook payload from stdin. Handles both payload formats:
  camelCase  (preToolUse): {"toolName": "...", "toolArgs": "<json string>", ...}
  PascalCase (PreToolUse): {"tool_name": "...", "tool_input": {...}, ...}
Prints a deny decision to stdout when a rule matches; prints nothing otherwise, which leaves
the normal permission flow in charge. If the payload has no recognizable tool name, it's
scanned anyway rather than waved through.

Non-shell tools (file edits etc.) are skipped, so a file that merely mentions
"terraform apply" is not blocked.

This is a best-effort blocklist, not a security boundary: a command spelled in an unexpected
way, or run from a script, can get past it. Scope credentials so a miss can't do damage.
To change what's blocked, edit the rules below and run tests/hook.ps1.
#>

$payload = [Console]::In.ReadToEnd()

function Get-Field($obj, [string[]]$names) {
    foreach ($n in $names) { if ($obj -is [System.Collections.IDictionary] -and $obj.Contains($n) -and $null -ne $obj[$n]) { return $obj[$n] } }
    return $null
}

$toolName = ''
$command = $null
try {
    $p = $payload | ConvertFrom-Json -AsHashtable
    $toolName = [string](Get-Field $p 'toolName', 'tool_name')
    $toolArgs = Get-Field $p 'toolArgs', 'tool_input'
    if ($toolArgs -is [string]) { try { $toolArgs = $toolArgs | ConvertFrom-Json -AsHashtable } catch { } }
    $cmd = Get-Field $toolArgs 'command', 'cmd', 'script'
    if ($cmd) { $command = [string]$cmd }
} catch { }

# Skip known non-shell tools. Unknown or missing names are scanned.
if ($toolName -and $toolName -notmatch '(?i)bash|shell|powershell|pwsh|terminal|exec|command|run') { exit 0 }

# Prefer the parsed command; fall back to the raw payload with JSON punctuation blanked out.
$text = if ($command) { $command } else { $payload -replace '\\"', ' ' -replace '\\[ntr]', ' ' -replace '[{}\[\],:"]', ' ' }

function Deny([string]$what) {
    if ($what.Length -gt 80) { $what = $what.Substring(0, 80) }
    [ordered]@{
        permissionDecision       = 'deny'
        permissionDecisionReason = "Blocked by guardrail hook ($what). Infrastructure changes are run by the user, not the agent. Show the exact command and stop."
    } | ConvertTo-Json -Compress
    exit 0
}

# One command's worth of text: stops at a command separator.
$seg = '[^;|&\n]*?'
# A tool name as a word, optionally with a Windows extension: terraform, terraform.exe.
function Tool([string]$names) { "(?<![\w.-])($names)(\.exe|\.cmd)?(?![\w.-])" }
# A verb as its own argument, optionally quoted: apply, 'apply', "apply".
function Verb([string]$verbs) { "\s['""]?($verbs)['""]?(?=\s|$|[;|&)])" }

$rules = @(
    # Terraform / OpenTofu / Terragrunt state-changing commands
    (Tool 'terraform|tofu|terragrunt') + $seg + (Verb 'apply|destroy|import|taint|untaint|force-unlock|apply-all|destroy-all|run-all')
    (Tool 'terraform|tofu|terragrunt') + $seg + '\sstate\s+(rm|mv|push|replace-provider)(?=\s|$)'
    # Kubernetes / Helm / helmfile
    (Tool 'kubectl') + $seg + (Verb 'apply|delete|create|replace|patch|scale|drain|cordon|uncordon|edit|label|annotate|taint|exec|cp|set|autoscale|expose|run')
    (Tool 'kubectl') + $seg + '\srollout\s+(restart|undo|pause|resume)(?=\s|$)'
    (Tool 'helm') + $seg + (Verb 'install|upgrade|uninstall|delete|rollback')
    (Tool 'helmfile') + $seg + (Verb 'apply|sync|destroy|delete|deps')
    # git reads that write a file: git diff/log/show --output=<path>
    (Tool 'git') + $seg + '\s--output(=|\s)'
)

foreach ($rule in $rules) {
    $m = [regex]::Match($text, $rule, 'IgnoreCase')
    if ($m.Success) { Deny (($m.Value -replace '["\\]', '').Trim()) }
}

# AWS CLI: allow read operations only; everything else is denied. Walks past global options
# (with or without values) to find the service and operation.
$awsReadOps = '^(describe|get|list|head|query|scan|search|lookup|wait|help|filter|validate|batch-get|select|tail)'
$awsValueOpts = '^--(profile|region|output|query|endpoint-url|cli-read-timeout|cli-connect-timeout|ca-bundle|color|cli-binary-format)$'
foreach ($m in [regex]::Matches($text, (Tool 'aws') + '([^;|&\n)]*)', 'IgnoreCase')) {
    $tokens = @($m.Groups[3].Value.Trim() -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.Trim('''', '"') })
    $words = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $tokens.Count -and $words.Count -lt 2; $i++) {
        $t = $tokens[$i]
        if ($t.StartsWith('-')) { if ($t -match $awsValueOpts) { $i++ }; continue }
        $words.Add($t.ToLowerInvariant())
    }
    if ($words.Count -lt 2) { continue }             # e.g. `aws --version`, `aws help`
    $service, $op = $words[0], $words[1]
    if ($service -eq 's3') {
        if ($op -in 'ls', 'presign', 'help') { continue }
        Deny "aws s3 $op"
    }
    if ($op -notmatch $awsReadOps) { Deny "aws $service $op" }
}

exit 0
