---
name: resume-task
description: Re-orient at the start of a session on in-progress work. Use when asked to resume, pick up, or continue work in this repo.
---

# Resume task

Gather state without changing anything:

1. Read `NOTES.md` at the repo root, if present.
2. Run `git status` (it names the current branch) and `git log --oneline -10`.
3. If NOTES.md has a State section, recompute it the same way: `git status --porcelain
   --untracked-files=all` (skip `NOTES.md`), then `git hash-object -- <files>`. Compare the
   first 7 characters per file.
4. If the GitHub CLI is available, check for an open PR on the current branch.

Then reply with:

- **Where things stand:** two or three lines.
- **Next step:** the single next action, taken from NOTES.md if it says so.
- **Mismatches:** anything that contradicts NOTES.md. List every file whose hash changed, that
  appeared, or that disappeared since the State fingerprint, and say "changed since handoff".
  Also flag a branch the notes don't name. If there's no State section, say drift inside
  uncommitted files can't be checked.

Do not start the next step until it is confirmed.
