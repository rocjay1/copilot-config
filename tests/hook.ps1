#!/usr/bin/env pwsh
<#
Offline test for the guardrail hook (home/hooks/scripts/block-mutations.ps1). No Copilot
session and no premium requests: feeds sample payloads to the hook and checks its decision.

  tests/hook.ps1
#>

$hook = Join-Path (Split-Path -Parent $PSScriptRoot) 'home/hooks/scripts/block-mutations.ps1'
$pwshExe = (Get-Process -Id $PID).Path

# expect, command. Each command is tested as a bash call (camelCase payload) and a
# powershell call (PascalCase payload).
$cases = @(
    # Terraform family
    ,@('deny', 'cd infra && terraform apply -auto-approve')
    ,@('deny', 'terraform destroy')
    ,@('deny', 'terraform.exe apply')
    ,@('deny', "& terraform 'apply'")
    ,@('deny', 'terraform -chdir=infra apply')
    ,@('deny', 'terraform -var-file "prod.tfvars" apply')
    ,@('deny', 'terraform state rm aws_s3_bucket.b')
    ,@('deny', 'terragrunt apply-all')
    ,@('deny', 'tofu import x y')
    ,@('allow', 'terraform plan')
    ,@('allow', 'terraform plan -destroy')
    ,@('allow', 'terraform validate')
    ,@('allow', 'terraform state list')
    # AWS: reads allowed, everything else denied
    ,@('deny', 'aws ec2 terminate-instances --instance-ids i-1')
    ,@('deny', 'aws --profile prod --region us-east-1 ec2 terminate-instances --instance-ids i-1')
    ,@('deny', 'aws.exe ec2 terminate-instances --instance-ids i-1')
    ,@('deny', 'aws ssm send-command --document-name x')
    ,@('deny', 'aws route53 change-resource-record-sets --hosted-zone-id z')
    ,@('deny', 'aws kms schedule-key-deletion --key-id k')
    ,@('deny', 'aws iam add-user-to-group --user-name u --group-name g')
    ,@('deny', 'aws s3 rm s3://b/k')
    ,@('deny', 'aws s3 sync . s3://b')
    ,@('deny', 'aws --no-cli-pager lambda invoke --function-name f out.json')
    ,@('allow', 'aws ec2 describe-instances')
    ,@('allow', 'aws --profile prod sts get-caller-identity')
    ,@('allow', 'aws s3 ls s3://b')
    ,@('allow', 'aws logs tail /aws/lambda/f')
    ,@('allow', 'aws dynamodb query --table-name t')
    ,@('allow', 'aws --version')
    # Kubernetes / Helm
    ,@('deny', 'kubectl -n x delete pod y')
    ,@('deny', 'kubectl --context "a b" delete pod y')
    ,@('deny', 'kubectl rollout restart deploy/x')
    ,@('deny', 'kubectl set image deploy/x c=img')
    ,@('deny', 'kubectl exec -it pod -- sh')
    ,@('deny', 'helm upgrade a b')
    ,@('deny', 'helm -n prod upgrade a b')
    ,@('deny', 'helm --kube-context x uninstall a')
    ,@('deny', 'helm.exe delete a')
    ,@('deny', 'helmfile apply')
    ,@('allow', 'kubectl get pods')
    ,@('allow', 'kubectl describe pod create-job')
    ,@('allow', 'kubectl rollout status deploy/x')
    ,@('allow', 'helm list -A')
    # Tool names inside arguments are not commands (commit messages, PR bodies)
    ,@('allow', 'git commit -m "Lock the AWS provider, and add tests"')
    ,@('allow', 'git commit -m "Document terraform apply steps"')
    ,@('allow', 'gh pr create --body "Run kubectl delete pod x to retry"')
    # ...but commands in the usual wrappers and prefixes still are
    ,@('deny', 'bash -c "terraform apply"')
    ,@('deny', 'pwsh -Command "aws ec2 terminate-instances --instance-ids i-1"')
    ,@('deny', 'echo done; aws s3 rm s3://b/k')
    ,@('deny', 'TF_LOG=1 terraform apply')
    ,@('deny', 'sudo kubectl delete pod x')
    ,@('deny', 'echo $(aws ec2 terminate-instances --instance-ids i-1)')
    # Prose inside quotes, heredocs, and here-strings is not a command, even across lines
    ,@('allow', "gh pr create --title `"feat(s3): add module`" --body `"## Why`nPlan-time mocks; AWS provider >= 6.0, < 7.0.`n- Policy uses aws:SourceAccount`"")
    ,@('allow', "git commit -m `"chore: note that terraform apply runs in CI; kubectl delete is manual`"")
    ,@('allow', "gh pr create --body-file - <<'EOF'`nLock the AWS provider; terraform apply later`nEOF")
    ,@('allow', "`$body = @'`nRun terraform apply after review; aws s3 rm is manual`n'@; gh pr create --body `$body")
    # ...while commands inside quotes that are actually run are still checked
    ,@('deny', 'bash -c "echo hi; terraform apply"')
    ,@('deny', 'echo "$(aws ec2 terminate-instances --instance-ids i-1)"')
    ,@('deny', "pwsh -Command `"Get-Date; helm upgrade a b`"")
    # git reads that write files
    ,@('deny', 'git log -p --output=/tmp/x')
    ,@('deny', 'git diff --output ~/.copilot/hooks/guardrails.json')
    ,@('allow', 'git log --oneline -5')
    ,@('allow', 'git diff --stat')
    # Redirects into Copilot's own configuration (cop's deny rule only covers the edit tools)
    ,@('deny', 'echo x > ~/.copilot/hooks/allow.json')
    ,@('deny', 'echo x >> .copilot/hooks/allow.json')
    ,@('deny', 'printf x>.copilot/cop.psd1')
    ,@('deny', 'cat a 1> "C:\Users\me\.copilot\hooks\a.json"')
    ,@('deny', 'echo x *> $env:COPILOT_HOME/hooks/a.json')
    ,@('deny', 'echo x > ${COPILOT_HOME}/skills/x/SKILL.md')
    ,@('deny', 'echo x > ../cop.psd1')
    ,@('deny', "echo x > '/home/me/.copilot/config.json'")
    ,@('deny', 'git log > out.txt; echo x > ~/.copilot/a')
    ,@('allow', 'echo x > notes.txt')
    ,@('allow', 'cat ~/.copilot/config.json')
    ,@('allow', 'git status 2>&1')
    ,@('allow', 'echo x > copilot-notes.txt')
    # ...including quoted, escaped, or indirect paths (PR #18 review)
    ,@('deny', 'echo x >"$HOME"/.copilot/hooks/a.json')
    ,@('deny', 'echo x > ~/".copilot"/hooks/a.json')
    ,@('deny', 'echo x > ~/.cop""ilot/a')
    ,@('deny', 'echo x >~/.cop`ilot/a')
    ,@('deny', 'p=~/.copilot/a.json; echo x > $p')
    ,@('deny', 'cd ~/.copilot; echo x > hooks.json')
    ,@('deny', 'echo x >> "C:\Program Files\x\.copilot\a.json"')
    ,@('deny', 'bash -c "echo x > ~/.copilot/a"')
    ,@('deny', "cat > ~/.copilot/hooks/a.json <<'EOF'`n{}`nEOF")
    # ...but a > in prose is not a redirect, and other streams don't count
    ,@('allow', "printf '%s\n' 'echo x > ~/.copilot/hooks/a.json'")
    ,@('allow', 'git commit -m "docs: never run echo x > ~/.copilot/y"')
    ,@('allow', 'ls ~/.copilot 2>/dev/null')
    ,@('allow', 'Get-ChildItem ~/.copilot 2>$null')
    # the friction-log skill's append: tee isn't pre-approved, so it prompts instead
    ,@('allow', "printf '%s\n' '- 2026-10-14 [other] x' | tee -a `"`${COPILOT_HOME:-`$HOME/.copilot}/friction-log.md`"")
    # Ways to make a pre-approved read run code
    ,@('deny', 'git -c core.fsmonitor=./x.sh status')
    ,@('deny', 'git -C sub -c diff.external=./x.sh diff')
    ,@('deny', 'git --no-pager -c core.pager=./x.sh log')
    ,@('deny', 'git --config-env=diff.external=X diff')
    ,@('deny', 'git --git-dir=evil status')
    ,@('deny', 'git --work-tree=. --git-dir evil diff')
    ,@('deny', 'git.exe --exec-path=evil status')
    ,@('deny', 'GIT_EXTERNAL_DIFF=./x.sh git diff')
    ,@('deny', 'GIT_DIR=evil git status')
    ,@('deny', 'export GIT_CONFIG_COUNT=1; git status')
    ,@('deny', 'env GIT_CONFIG_PARAMETERS=x git log')
    ,@('deny', '$env:GIT_EXTERNAL_DIFF = "./x.ps1"; git diff')
    ,@('deny', 'RIPGREP_CONFIG_PATH=.rgrc rg foo')
    ,@('deny', 'TF_DATA_DIR=evil tf-check validate')
    ,@('deny', 'TF_CLI_CONFIG_FILE=x.tfrc tf-check validate')
    ,@('deny', 'rg --pre ./x.sh foo')
    ,@('deny', 'rg -i --pre=./x.sh foo')
    ,@('deny', 'rg --pre-glob "*.pdf" --pre pdftotext foo')
    ,@('allow', 'git -C sub status')
    ,@('allow', 'git log -c -1')
    ,@('allow', 'git diff --cached')
    ,@('allow', 'git log --grep=GIT_DIR')
    ,@('allow', 'rg --pretty foo')
    ,@('allow', 'git commit -m "explain GIT_DIR=x and rg --pre"')
)

function Invoke-Hook([string]$payload) {
    $out = $payload | & $pwshExe -NoProfile -NonInteractive -File $hook
    if ($LASTEXITCODE -ne 0) { return "exit $LASTEXITCODE" }
    if ("$out" -match '"permissionDecision":"deny"') { 'deny' } else { 'allow' }
}

$fail = 0; $total = 0
function Test-One([string]$expect, [string]$label, [string]$payload) {
    $script:total++
    $got = Invoke-Hook $payload
    if ($got -ne $expect) { $script:fail++; Write-Output ("FAIL  want {0,-5} got {1,-5}  {2}" -f $expect, $got, $label) }
}

foreach ($c in $cases) {
    $expect, $cmd = $c
    $argsJson = @{ command = $cmd } | ConvertTo-Json -Compress
    Test-One $expect "bash: $cmd" (@{ toolName = 'bash'; toolArgs = $argsJson } | ConvertTo-Json -Compress)
    Test-One $expect "powershell: $cmd" (@{ tool_name = 'powershell'; tool_input = @{ command = $cmd } } | ConvertTo-Json -Compress)
}

# Payload shapes
Test-One 'allow' 'file edit mentioning terraform apply' `
    (@{ toolName = 'edit'; toolArgs = (@{ path = 'x.md'; content = 'run terraform apply later' } | ConvertTo-Json -Compress) } | ConvertTo-Json -Compress)
Test-One 'deny' 'unknown payload shape is still scanned' '{"tool":"bash","input":{"command":"terraform apply"}}'
Test-One 'deny' 'unparseable payload is still scanned' 'not json terraform apply'

# Redirects resolved against the payload's cwd, and a COPILOT_HOME or COP_CONF with any name
function Shell([string]$cmd, [string]$dir = '') {
    $p = @{ toolName = 'bash'; toolArgs = (@{ command = $cmd } | ConvertTo-Json -Compress) }
    if ($dir) { $p.cwd = $dir }
    $p | ConvertTo-Json -Compress
}
$tmp = [System.IO.Path]::GetTempPath()
Test-One 'deny' 'relative redirect from inside .copilot' (Shell 'echo x > hooks/allow.json' (Join-Path $tmp '.copilot'))
$saved = $env:COPILOT_HOME, $env:COP_CONF
try {
    $env:COP_CONF = Join-Path $tmp 'cfg/work.psd1'
    Test-One 'deny' 'redirect into a custom COP_CONF' (Shell "echo x > $env:COP_CONF")
    Test-One 'deny' 'relative redirect into a custom COP_CONF' (Shell 'echo x > work.psd1' (Join-Path $tmp 'cfg'))
    Test-One 'allow' 'redirect next to a custom COP_CONF' (Shell ('echo x > ' + (Join-Path $tmp 'cfg/work.psd1.bak')))
    $env:COP_CONF = $null

    $env:COPILOT_HOME = Join-Path ([System.IO.Path]::GetTempPath()) 'my-copilot'
    $custom = Join-Path $env:COPILOT_HOME 'hooks/a.json'
    Test-One 'deny' 'redirect into a custom COPILOT_HOME' (@{ toolName = 'bash'; toolArgs = (@{ command = "echo x > $custom" } | ConvertTo-Json -Compress) } | ConvertTo-Json -Compress)
    $other = Join-Path ([System.IO.Path]::GetTempPath()) 'my-copilot-other/a.json'
    Test-One 'allow' 'redirect next to a custom COPILOT_HOME' (@{ toolName = 'bash'; toolArgs = (@{ command = "echo x > $other" } | ConvertTo-Json -Compress) } | ConvertTo-Json -Compress)
} finally { $env:COPILOT_HOME, $env:COP_CONF = $saved }

Write-Output ''
Write-Output "hook cases: $($total - $fail)/$total passed"
exit ($fail -gt 0 ? 1 : 0)
