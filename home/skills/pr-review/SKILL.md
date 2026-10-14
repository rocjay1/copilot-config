---
name: pr-review
description: Work through review feedback on the current branch's pull request - fetch unresolved threads, triage them, fix agreed ones in batches, then reply, resolve, and re-request review when asked. Use when asked to read, address, or close out a PR review.
---

# PR review

Prevents: review feedback applied without triage, threads left unresolved after fixes, and
fumbled GitHub API calls (inline threads are only reachable through `gh api`).

Use the work profile: `gh api` prompts there and is denied in research. Fetch with one
command so it's one approval. `{owner}` and `{repo}` are filled in by `gh` from the current
repo; don't look them up.

1. Fetch the PR (`gh pr view --json number,url,reviewDecision`), then in one command:
   - unresolved threads:
     `gh api graphql -F owner='{owner}' -F name='{repo}' -F n=<number> -f query='query($owner:String!,$name:String!,$n:Int!){repository(owner:$owner,name:$name){pullRequest(number:$n){reviewThreads(first:100){nodes{id isResolved isOutdated path line comments(first:20){nodes{author{login} body}}}}}}}'`
   - review summaries: `gh api repos/{owner}/{repo}/pulls/<number>/reviews --jq '.[] | {user: .user.login, state, body}'`
2. Triage every unresolved thread in a table: file:line (or "outdated"), the point in a few
   words, and a verdict with a one-line reason: **agree**, **disagree**, **already fixed**
   (outdated and addressed by a later commit), or **needs you** (a judgment call).
3. Propose fixes for the agreed threads and wait for approval. Then implement following the
   batching rule in the personal instructions, and run the repo's validation.
4. Commit and push only when asked.
5. When asked to close out, draft a one-sentence reply per thread (e.g. "Fixed in `abc1234`:
   removed the output." or the reason for disagreeing). Show all replies, wait for approval,
   then post each and resolve only the fixed and already-fixed threads:
   - reply: `gh api graphql -f id=<thread id> -f body='<reply>' -f query='mutation($id:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$id,body:$body}){comment{url}}}'`
   - resolve: `gh api graphql -f id=<thread id> -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}'`
6. When asked to re-request review: `gh pr edit <number> --add-reviewer @copilot` (with the
   `@`; a bare `copilot` fails). For a person, use their login.

Stop conditions:
- Never resolve a thread you disagreed with or marked "needs you"; reply and leave it open
  for the reviewer.
- Never dismiss a review, approve, or merge.
