# Working with Copilot CLI: sessions, context, and configuration

Notes from a working session on 2026-10-12. Companion to this repo's README.

## The core idea

Context is a working set, not a history log. Model quality drops as the window fills with
stale or irrelevant material: failed attempts, long tool output, abandoned plans. Every
decision below is about keeping the working set relevant to the task in front of you.

## Sessions: fresh vs. continuing

**Start fresh (`/clear` or `/new`) when:**
- The task changes: new ticket, new bug, new question.
- You've hit a dead end. After two or three corrections on the same thing, the failed
  approaches in context are anchoring the model. A clean session with a better prompt wins.
  (The personal instructions tell Copilot to suggest this after a second correction.)
- You finish a unit of work (commit, PR).

`/clear` accepts the next task inline, so you can reset and kick off in one step.

**Continue when** the next step depends on state that's expensive to rebuild, like
mid-debug hypotheses. `copilot --continue` resumes the most recent session;
`copilot --resume` (or `/resume` in-session) picks from a list.

**Make fresh starts cheap.** Durable state lives in files, not chat:
- Repo conventions: `.github/copilot-instructions.md` (`copilot init` scaffolds it).
- Task state: `NOTES.md`, written by the `handoff` skill before you clear.
- Pull files in explicitly with `@path`.

## Compaction

- `/context` shows token usage; check it before deciding.
- Compact at breakpoints **within one task**, e.g. after exploration, before implementation.
  Not on a schedule.
- Steer it: tell `/compact` what to keep and what to drop.
- Compaction is lossy. Exact error strings, resource addresses, plan output you care about,
  and version pins go in a file.
- If the task itself is changing, `/clear` plus a handoff note beats compacting. Compaction
  keeps a blurry version of everything; a handoff keeps a sharp version of what matters.

## Forking and parallel work

- **`/fork`** (v1.0.45+; `/fork "name"` since v1.0.47; `/branch` alias since v1.0.64) copies
  the session into an independent one sharing history up to that point. Use it to compare
  two approaches, try a risky refactor, or chase a tangent without polluting the main thread.
- **`/fleet`** delegates to subagents in parallel. Good for broad, separable work. Typical
  flow: plan first, then `/fleet implement the plan`.
- **`/delegate`** hands off with more autonomy, ending in a PR. Good for well-specified chores.
- Older Copilot CLI releases were affected by issue #3013, where `preToolUse` and `postToolUse`
  hooks didn't apply to subagent calls. Current releases include the fix; update your CLI and
  test your installed version before relying on hooks to guard `/fleet` subagents.

## Worktrees

Worktrees are a good way to run tickets in parallel or take an interruption without stashing:
each ticket gets its own folder, branch, and `NOTES.md`. They went wrong in agent-driven setups
because the agent created them and nothing kept track. So:

- **You create and remove them.** Copilot can't create one without asking.
  `git worktree add ../<repo>-<ticket> -b <ticket>` to start, and
  `git worktree remove ../<repo>-<ticket>` once the PR merges.
- **One worktree per ticket**, named after the ticket.
- **`resume-task` lists the others** that have uncommitted changes or notes. Its
  `git worktree list` prompts in `cop` (approve it), and is denied in `cop research`.
- `git worktree list` shows them all; check it when you finish a ticket.

## Daily loop

One ticket = one branch = one session = one `NOTES.md`. You create or link the ticket; the
agent only reads it. `NOTES.md` is your working state, not part of the change: keep it out of
commits by adding it once to your global gitignore (`git config --global core.excludesFile`) or
to each repo's `.git/info/exclude`.

1. `cop research` to investigate: tickets, logs, monitoring, PR history. It can't edit files,
   and the common external writes are denied; anything else still prompts, so read what you
   approve. When you `/exit`, `cop` prints `cop work --resume <id>`: run it to continue the same
   session, findings included, with work permissions. The resumed session gets the same
   handoff check on exit as one `cop` started.
2. `cop` in the repo to make the change. Say "resume" to run `resume-task` if continuing work.
3. Ask it to work the ticket (`work-ticket`). Press Shift+Tab into plan mode first if you want to
   edit the plan in your editor (Ctrl+Y) before approving it. It proposes a plan and waits, then changes at most
   3 files or about 200 lines per batch. File edits in the working folder don't prompt in `cop`;
   the stop after each batch is your review point. Review each batch's diff, editing in your
   editor with completions where you'd rather write it yourself. Small, obvious edits skip the
   plan; just ask for them.
4. When it's done, it runs the approved validation, reviews the local changes with Copilot's
   built-in `code-review` and `security-review` subagents (the agents behind `/review` and
   `/security-review`), triages their findings, and writes the PR title and description in chat. Open the PR
   (or approve the prompt) and ask for a Copilot review. Then `/exit` and start a fresh `cop`
   for the review (`work-ticket` and `pr-review` both remind you, and neither polls for it): a session that carried the research, the change, and the PR re-sends all of
   that context on every call, and one such session used about 180 AI credits. When the review
   lands, ask the new session to work through it (`pr-review`); it reads the PR from GitHub, so
   it doesn't need the old context: it triages each thread, proposes fixes and waits, and only replies,
   resolves threads, or re-requests review when you ask. Its `gh api` calls prompt.
5. Update `NOTES.md` with the handoff, commit the change itself if you're ready, then `/clear`
   or `/exit`. The easy way: just `/exit`. If `NOTES.md` is out of date, `cop` offers to run the
   handoff in that same session on Copilot's cheapest suitable model (about 0.5 AI credits
   measured, against about 4 for asking inside the session on its own model). Ask inside the
   session instead when the notes need the session model's judgment; `HandoffModel` in
   `cop.psd1` changes the exit default. `cop --check-notes` shows the status.

Use `/fork "name"` to compare alternatives. Avoid `/fleet` for changes you need to review:
it produces a lot at once, and whether hooks guard subagents depends on your CLI version (#3013
above).

## Tuning it in the first weeks

The defaults are a starting point; adjust them from evidence, not guesses.

- **When something gets in the way,** ask Copilot to log it ("log friction: that batch was too
  big to review"). The `friction-log` skill appends one line to `~/.copilot/friction-log.md`,
  about the tool's behavior, never the work.
- **Once a week,** run `scripts/friction-report.ps1` and read it on the same machine. It shows
  which commands keep prompting (candidates for `ReadTools`), what got blocked, which skills
  ran, and what sessions cost, alongside your friction notes.
- **Change only what the report shows:** add reads that prompted repeatedly, tune the batch
  size, change the handoff default. Bring anything surprising back to this repo as a change,
  described in your own words: work details don't leave the work machine.
- **Revisit after a few weeks:** `/delegate` for side chores (docs, small refactors) if they pile
  up and your org enables Copilot cloud agent; you'd still review its PR.
- **Stop and investigate** if something outside your machine changed without your approval.
- **Sessions have a 100-credit soft cap.** If you hit it mid-task, `/limits` raises it; if you
  hit it often, set `MaxAiCredits` in `cop.psd1`.

## Configuration layers

The principle: everything always-on is paid for in every session, so keep instructions
tiny and push procedures into skills that load only when needed.

| Layer | Location | Loaded | Use for |
|---|---|---|---|
| Personal instructions | `~/.copilot/copilot-instructions.md` | Always | Your working style |
| Repo instructions | `.github/copilot-instructions.md` | Always | Team conventions (change by PR) |
| Path instructions | `.github/instructions/*.instructions.md` | When `applyTo` matches | Tool/language rules, e.g. Terraform |
| Skills | `.github/skills/`, `~/.copilot/skills/` (also `.claude/`, `.agents/`) | On demand | Multi-step procedures |
| Custom agents | `.github/agents/`, `~/.copilot/agents/` (`*.agent.md`) | When selected | Narrow roles with restricted tools |
| Hooks | `.github/hooks/*.json`, `~/.copilot/hooks/*.json` | Every matching tool call | Automated guardrails |

Things to know:
- Copilot CLI **combines** `.github/copilot-instructions.md`, `AGENTS.md`, `CLAUDE.md`,
  `.claude/CLAUDE.md`, and `GEMINI.md`. Overlapping files left over from other tools are a
  prime suspect for idiosyncratic behavior. Keep one root file.
- `applyTo: "**"` makes a path-scoped file always-on.
- `@` includes work in the root files but not in `*.instructions.md` or `GEMINI.md`.
- Instruction changes apply to the **next** session. `/skills reload` picks up new skills.
- Use `~/.copilot/copilot-instructions.md` for always-on personal rules, not
  `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` (its scoping changed after v1.0.65; copilot-cli #3987).

## Where does a new rule go?

```
Could this cause an unacceptable side effect?  → hook plus independent controls
Is it a sequence of steps for a situation?     → skill
Does it apply only to certain files?           → *.instructions.md with applyTo
Is it the team's convention for this repo?     → repo copilot-instructions.md (via PR)
Is it how you like to work, everywhere?        → personal copilot-instructions.md
Does it need its own tool limits / persona?    → custom agent (rarely)
Can't name the failure it prevents?            → don't add it
```

## Diagnosing over-engineered config

1. Run `scripts/audit.ps1 /path/to/repo`. Compare always-on words to this repo's heuristic
   budgets (personal ≤ 300, repo ≤ 500); these are not GitHub limits.
2. Look for the same topic in multiple files, especially `AGENTS.md` / `CLAUDE.md`.
3. Look for skills with overlapping descriptions or duplicate names across locations.
4. Run `/instructions` and `/context` in a fresh session to check loaded instructions and
   actual starting context; the audit is only an estimate.
5. Remove, don't add. Re-test in a new session after each removal.

## Open items

- Rerun `tests/hook.ps1` and `tests/smoke.ps1` after `copilot update`. They cover the
  profiles' allow and deny rules and the guardrail hook (verified on 1.0.97 as a user-level
  hook). They don't cover subagent calls; test those before relying on hooks for `/fleet`.
- Atlassian tool names in `templates/cop.psd1.example` were checked against the v2 endpoint on a
  test site. Recheck with `/mcp show atlassian` if Atlassian changes its tools.
- Verify the `tools:` names and other frontmatter in `reviewer.agent.md` against your CLI
  version.
- Run the audit on the existing work config and review it alongside a screenshot of the
  behavior.

## Compatibility and safety

This configuration targets **Copilot CLI**. Configuration discovery, hooks, and supported
frontmatter can differ in Copilot cloud agent and IDEs, and can change between CLI versions;
check the documentation for the surface and version you use. Hooks are automated guardrails,
not security boundaries. Pair them with permissions, sandboxing, and narrowly scoped
credentials when a side effect is unacceptable.

## Sources

- [Copilot CLI command reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
- [Adding custom instructions for Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions)
- [Creating agent skills](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-skills)
- [Copilot CLI hooks reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-hooks-reference)
- [Dynamic workflows (fleet vs. autopilot)](https://docs.github.com/en/copilot/concepts/agents/dynamic-workflows)
- [awesome-copilot Learning Hub: /fork](https://github.com/github/awesome-copilot/commit/e737a33955bfcfa680249b10d761f6c66a4a9f06)
- [copilot-cli #3013: hooks and subagents](https://github.com/github/copilot-cli/issues/3013)
- [copilot-cli #3987: COPILOT_CUSTOM_INSTRUCTIONS_DIRS change](https://github.com/github/copilot-cli/issues/3987)
