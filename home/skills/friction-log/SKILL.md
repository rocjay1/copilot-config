---
name: friction-log
description: Append a one-line note about how Copilot or this configuration behaved to the local friction log. Use when asked to log friction, note a problem with the tool, or record feedback about a session.
---

# Friction log

Prevents: losing the evidence needed to tune this configuration (which prompts, batches,
skills, or costs got in the way).

The log is `~/.copilot/friction-log.md` (or `$COPILOT_HOME/friction-log.md`). It stays on this
machine; `scripts/friction-report.ps1` summarizes it with the session logs.

1. Turn the request into one entry about the **tool's behavior**, not the work:
   `- YYYY-MM-DD [category] note`, under 200 characters, today's date.
   Categories: `batching`, `prompts`, `skills`, `handoff`, `resume`, `review`, `cost`,
   `safety`, `other`. Use the user's wording where it fits; add what just happened in this
   session if it makes the note clearer (e.g. "batch was 5 files despite the 3-file rule").
2. Keep work details out: no ticket keys, repo, branch, resource, host, or account names,
   URLs, IDs, or code. Replace them with generic words ("a Terraform module", "a Jira
   ticket"). If you replaced anything, say what.
3. Append the line with one shell command, creating the file if needed, e.g.
   PowerShell: `Add-Content -Path (Join-Path ($env:COPILOT_HOME ?? "$HOME/.copilot") 'friction-log.md') -Value '<entry>'`
   bash: `printf '%s\n' '<entry>' | tee -a "${COPILOT_HOME:-$HOME/.copilot}/friction-log.md"`
   Neither command is pre-approved, so it prompts once. Don't use `>>`: the guardrail hook
   blocks redirects into the Copilot folder.
4. Reply with the entry as written, and stop. Don't change anything else.
