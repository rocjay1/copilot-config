#!/usr/bin/env bash
# preToolUse guardrail: deny shell commands that mutate infrastructure.
#
# Reads the hook payload from stdin. Handles both payload formats:
#   camelCase  (preToolUse): {"toolName": "...", "toolArgs": "<json string>", ...}
#   PascalCase (PreToolUse): {"tool_name": "...", "tool_input": {...}, ...}
# Prints a deny decision to stdout when a pattern matches; prints nothing otherwise,
# which leaves the normal permission flow in charge.
#
# No jq dependency: the tool name is extracted with a regex, and the raw payload is
# scanned only when the tool is a shell tool, so file edits that merely mention
# "terraform apply" are not blocked.
#
# To change what's blocked, edit PATTERNS. Keep it to things that must never happen.

set -u

payload="$(cat)"

tool_name="$(printf '%s' "$payload" \
  | grep -oE '"tool_?[Nn]ame"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -n1 \
  | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')"

# Only inspect shell-like tools. Tool names vary by version; match loosely.
shopt -s nocasematch
case "$tool_name" in
  *bash*|*shell*|*powershell*|*terminal*|*exec*) ;;
  *) exit 0 ;;
esac
shopt -u nocasematch

# `aws` followed by any global options (e.g. --profile p, --region r, --no-cli-pager),
# so options placed before the service name don't bypass the AWS patterns.
AWS='aws([[:space:]]+-[^[:space:]]*([[:space:]]+[^-[:space:]][^[:space:]]*)?)*'

PATTERNS=(
  # Terraform / OpenTofu / Terragrunt state-changing commands
  '(terraform|tofu|terragrunt)[^"]*[[:space:]](apply|destroy|import|taint|untaint|force-unlock)([^a-z-]|$)'
  '(terraform|tofu|terragrunt)[^"]*[[:space:]]state[[:space:]]+(rm|mv|push|replace-provider)'
  # AWS CLI mutating verbs (service subcommands)
  "$AWS"'[[:space:]]+[a-z0-9-]+[[:space:]]+(create|delete|put|update|modify|terminate|run|start|stop|reboot|attach|detach|associate|disassociate|authorize|revoke|restore|replace|register|deregister|enable|disable|tag|untag|set|reset|import|cancel|invoke|deploy)(-|[[:space:]]|$)'
  # AWS S3 high-level commands that write or delete
  "$AWS"'[[:space:]]+s3[[:space:]]+(rm|mv|cp|sync|rb|mb)([[:space:]]|$)'
  # Kubernetes / Helm
  'kubectl[^"]*[[:space:]](apply|delete|create|replace|patch|scale|drain|cordon|edit)([[:space:]]|$)'
  'helm[[:space:]]+(install|upgrade|uninstall|rollback)([[:space:]]|$)'
)

for pattern in "${PATTERNS[@]}"; do
  if printf '%s' "$payload" | grep -qiE -- "$pattern"; then
    matched="$(printf '%s' "$payload" | grep -oiE -- "$pattern" | head -n1 | tr -d '"\\' | cut -c1-80)"
    printf '{"permissionDecision":"deny","permissionDecisionReason":"Blocked by guardrail hook (%s). Infrastructure changes are run by the user, not the agent. Show the exact command and stop."}\n' "$matched"
    exit 0
  fi
done

exit 0
