---
name: resume-task
description: Re-orient at the start of a session on in-progress work. Use when asked to resume or pick up work in this repo. Not for requests to commit, push, or open or review a PR.
---

# Resume task

For re-orienting a fresh session from NOTES.md and git. To get a previous conversation back
instead, the user runs `cop --resume` (the session picker), which also returns to that
session's folder.

Gather state without changing anything:

1. Read `NOTES.md` at the repo root, if present.
2. Run `git status` (it names the current branch) and `git log --oneline -10`.
3. If NOTES.md has a State section, recompute it the same way: `git status --porcelain
   --untracked-files=all` (skip `NOTES.md`), then `git hash-object -- <files>`. Compare the
   first 7 characters per file, and compare the HEAD bullet with `git log --oneline -1`.
4. If the GitHub CLI is available, check for an open PR on the current branch.
5. List other worktrees: `git worktree list --porcelain`. For each one other than this, run
   `git -C <path> status --porcelain` and check whether `<path>/NOTES.md` exists. If the GitHub
   CLI is available, also check whether its branch's PR has merged: compare
   `gh pr list --head <branch> --state merged --json headRefOid --jq '.[].headRefOid'` with
   `git -C <path> rev-parse HEAD`. A match means the worktree's HEAD is what merged. A merged PR
   with a different HEAD means commits were added after the merge (or the branch was reused).
   If the list command is denied, say "other worktrees not checked" and carry on.

Then reply with:

- **Where things stand:** two or three lines.
- **Next step:** the single next action, taken from NOTES.md if it says so.
- **Mismatches:** anything that contradicts NOTES.md. List every file whose hash changed, that
  appeared, or that disappeared since the State fingerprint, and say "changed since handoff".
  If HEAD moved, list the commits since the recorded one (`git log --oneline <recorded>..HEAD`).
  Also flag a branch the notes don't name. If there's no State section, say drift inside
  uncommitted files can't be checked.
- **Other worktrees:** one line each for those with uncommitted changes, a NOTES.md, or a merged
  PR: path, branch, number of uncommitted files, whether it has notes, and "PR merged" if so.
  Omit clean ones without notes or a merged PR.
- **Ready to remove:** for each worktree whose HEAD matches a merged PR's head and that has no
  uncommitted changes, give the command for the user to run: `git worktree remove <path>`. Don't
  run it. If a merged one still has uncommitted changes, or commits after the merged head, say so
  instead; removing it would lose that work.

Do not start the next step until it is confirmed.
