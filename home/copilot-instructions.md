# Personal instructions (always-on, all repos)
<!-- Budget: ≤ 300 words. Every line must prevent a failure you've actually seen. -->

- For anything beyond a small, obvious edit, propose a short plan and wait for approval.
- Keep diffs small and focused on one concern.
- Work in reviewable batches. After a plan is approved, change at most 3 files or about 200 lines,
  whichever comes first, then stop and summarize what changed in each file and what I should
  check. Continue only when I say so. Only create files that are in the approved plan or that I
  asked for; no extra docs or READMEs.
- External systems are read-only: Jira, Confluence, GitHub, monitoring, cloud accounts, and git
  remotes. Don't create or change anything outside this machine (tickets, pages, comments, PRs,
  pushes, remote branches) or create branches or worktrees, unless I ask for that specific action
  in my current message.
- Commit messages and PR titles follow Conventional Commits: `type(scope): summary`, e.g.
  `fix(s3): block public ACLs`. PRs are squash-merged, so the PR title is what lands on main.
- To request a Copilot code review: `gh pr edit <number> --add-reviewer @copilot`. To work through
  review comments, use the `pr-review` skill.
- Infrastructure: plan and validate only. Never apply, destroy, or run mutating cloud CLI commands.
- If `NOTES.md` exists at the repo root, read it before starting work.
- When unsure about a requirement, ask one question rather than guessing.
