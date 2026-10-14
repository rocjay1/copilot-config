---
name: work-ticket
description: Work a ticket or change request locally, planned first and built in small reviewable batches, ending with a PR description written in chat. Never creates the PR itself. Use when asked to work a ticket, or for a change spanning several files. Not for small, obvious edits.
---

# Work ticket

Prevents: large changes landing in one pass that can't be reviewed.

Gather first:
- The ticket (read only) or the request in chat.
- The files the change touches, and the repo's validate or test commands.

1. Propose a plan and wait for approval. If the session is in plan mode, write it as the plan
   there, so it can be edited before it's approved. The plan covers:
   - each file to add or change, with one line on why;
   - what's out of scope;
   - how the change will be verified (e.g. `terraform validate`, `terraform plan`, or tests).
2. Implement in batches, following the batching rule in the personal instructions. In each
   batch summary, call out anything risky or non-obvious: IAM scope, deletions, renames,
   replaced resources, new dependencies.
3. When the plan is done, run the approved verification commands and report the results. For
   Terraform, use `tf-check fmt` and `tf-check validate` (pre-approved, read-only); `terraform
   init`, `test`, and `plan` prompt. Ask before each run of a command that needs cloud
   credentials or takes a state lock, such as `terraform plan`.
4. Review the local changes before any PR: run the built-in `code-review` and `security-review`
   subagents (the agents behind `/review` and `/security-review`; both read-only) in parallel
   with your task tool. Triage what they find like review comments: propose fixes for the ones
   worth fixing and wait, then apply them as a batch and rerun the verification.
5. Write the PR title and description in chat. The title is a Conventional Commits subject
   (it becomes the squash commit). The description covers what changed, why, how it was
   verified (including the local review), and what a reviewer should look at first. Link the
   ticket.
6. End by telling the user: after opening the PR and requesting a Copilot review, `/exit` and
   handle the review in a fresh `cop` with `pr-review`. This session's research and changes
   would be re-sent on every review call (one such session used about 180 AI credits).

Stop conditions:
- Commit only when asked. External writes follow the personal instructions.
- If the plan grows past about 10 files or covers more than one concern, stop and propose
  splitting it into separate PRs.
- If verification fails twice on the same issue, stop and report instead of trying more fixes.
