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
3. When the plan is done, run the approved verification commands and report the results. Ask
   before each run of a command that needs cloud credentials or takes a state lock, such as
   `terraform plan`.
4. Ask me to run `/review` and `/security-review` on the local changes, and wait. Triage what
   they find like review comments: propose fixes for the ones worth fixing, then apply them
   as a batch and rerun the verification.
5. Write the PR title and description in chat. The title is a Conventional Commits subject
   (it becomes the squash commit). The description covers what changed, why, how it was
   verified (including the local review), and what a reviewer should look at first. Link the
   ticket.

Stop conditions:
- Commit only when asked. External writes follow the personal instructions.
- If the plan grows past about 10 files or covers more than one concern, stop and propose
  splitting it into separate PRs.
- If verification fails twice on the same issue, stop and report instead of trying more fixes.
