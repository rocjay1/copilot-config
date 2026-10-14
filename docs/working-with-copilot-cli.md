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
- Known issue: `preToolUse` hooks reportedly don't fire for subagent tool calls
  (copilot-cli #3013). Don't rely on hooks to guard `/fleet` until that's fixed in your version.

## Daily loop

One ticket = one branch = one session = one `NOTES.md`. You create or link the ticket; the
agent only reads it. `NOTES.md` is your working state, not part of the change: keep it out of
commits by adding it once to your global gitignore (`git config --global core.excludesFile`) or
to each repo's `.git/info/exclude`.

1. `cop research` to investigate: tickets, logs, monitoring, PR history. It can't edit files, and the
   common external writes are denied; anything else still prompts, so read what you approve.
2. `cop` in the repo to make the change. Say "resume" to run `resume-task` if continuing work.
3. Ask it to work the ticket (`work-ticket`): it proposes a plan and waits, then changes at most
   3 files or about 200 lines per batch. Review each batch's diff, editing in your editor with
   completions where you'd rather write it yourself.
4. When it's done, it runs the approved validation and writes the PR description in chat. Open the PR
   (or approve the prompt), then iterate on Copilot's review.
5. Run `handoff` to update `NOTES.md`, commit the change itself if you're ready, then `/clear`.

Use `/fork "name"` to compare alternatives. Avoid `/fleet` for changes you need to review:
it produces a lot at once, and hooks reportedly don't guard subagents.

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
| Hooks | `.github/hooks/*.json`, `~/.copilot/hooks/*.json` | Every matching tool call | Hard guardrails |

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
Must it never happen, no matter what?          → hook
Is it a sequence of steps for a situation?     → skill
Does it apply only to certain files?           → *.instructions.md with applyTo
Is it the team's convention for this repo?     → repo copilot-instructions.md (via PR)
Is it how you like to work, everywhere?        → personal copilot-instructions.md
Does it need its own tool limits / persona?    → custom agent (rarely)
Can't name the failure it prevents?            → don't add it
```

## Diagnosing over-engineered config

1. Run `scripts/audit.ps1 /path/to/repo`. Compare always-on words to budget
   (personal ≤ 300, repo ≤ 500).
2. Look for the same topic in multiple files, especially `AGENTS.md` / `CLAUDE.md`.
3. Look for skills with overlapping descriptions or duplicate names across locations.
4. Run `/context` in a fresh session to see the real starting load.
5. Remove, don't add. Re-test in a new session after each removal.

## Open items

- Rerun `tests/smoke.ps1` after `copilot update`. It covers the profiles' allow and deny rules
  and the guardrail hook (verified on 1.0.97 as a user-level hook).
- Confirm the Atlassian tool names in `templates/cop.psd1.example` against `/mcp show` on a
  real site.
- Verify the `tools:` names in `reviewer.agent.md` for your CLI version.
- Run the audit on the existing work config and review it alongside a screenshot of the
  behavior.

## Sources

- [Copilot CLI command reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
- [Adding custom instructions for Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions)
- [Creating agent skills](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/create-skills)
- [Copilot CLI hooks reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-hooks-reference)
- [Dynamic workflows (fleet vs. autopilot)](https://docs.github.com/en/copilot/concepts/agents/dynamic-workflows)
- [awesome-copilot Learning Hub: /fork](https://github.com/github/awesome-copilot/commit/e737a33955bfcfa680249b10d761f6c66a4a9f06)
- [copilot-cli #3013: hooks and subagents](https://github.com/github/copilot-cli/issues/3013)
- [copilot-cli #3987: COPILOT_CUSTOM_INSTRUCTIONS_DIRS change](https://github.com/github/copilot-cli/issues/3987)
