---
name: resume-task
description: Re-orient at the start of a session on in-progress work. Use when asked to resume, pick up, or continue work in this repo.
---

# Resume task

Gather state without changing anything:

1. Read `NOTES.md` at the repo root, if present.
2. Run `git status` (it names the current branch) and `git log --oneline -10`.
3. If the GitHub CLI is available, check for an open PR on the current branch.

Then reply with:

- **Where things stand:** two or three lines.
- **Next step:** the single next action, taken from NOTES.md if it says so.
- **Mismatches:** anything in git that contradicts NOTES.md (uncommitted changes it doesn't mention, a branch it doesn't name).

Do not start the next step until it is confirmed.
