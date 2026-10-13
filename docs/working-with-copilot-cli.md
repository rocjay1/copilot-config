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
- Older Copilot CLI releases were affected by issue #3013, where `preToolUse` and `postToolUse`
  hooks didn't apply to subagent calls. Current releases include the fix; update your CLI and
  test your installed version before relying on hooks to guard `/fleet` subagents.

## Daily loop

1. `copilot` in the repo. Instructions load automatically; say "resume" to run the
   `resume-task` skill if continuing work.
2. Plan mode for anything non-trivial. After exploring, check `/context`, then `/compact`
   with focus instructions.
3. `/fork "name"` for alternatives; `/fleet` for parallelizable work.
4. Run `handoff` to update `NOTES.md`, commit, then `/clear`.

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

1. Run `scripts/audit.sh /path/to/repo`. Compare always-on words to this repo's heuristic
   budgets (personal ≤ 300, repo ≤ 500); these are not GitHub limits.
2. Look for the same topic in multiple files, especially `AGENTS.md` / `CLAUDE.md`.
3. Look for skills with overlapping descriptions or duplicate names across locations.
4. Run `/instructions` and `/context` in a fresh session to check loaded instructions and
   actual starting context; the audit is only an estimate.
5. Remove, don't add. Re-test in a new session after each removal.

## Open items

- Verify the guardrail hook in a disposable environment with blocked and allowed commands,
  likely bypass forms, and subagent calls. Confirm the hook's actual tool names and behavior
  against your installed CLI version before relying on it.
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
