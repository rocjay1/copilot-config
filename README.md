# copilot-config

A minimal, auditable framework for GitHub Copilot CLI configuration.

The goal is the **least** configuration that produces predictable behavior. Every line of
always-on context is paid for in every session and competes with every other line, so this
repo is built around keeping that surface small and putting each rule in exactly one place.

## Principles

1. **Small always-on budget.** Instruction files load into every session. Budgets:
   personal ≤ 300 words, repo root ≤ 500 words. `scripts/audit.sh` checks this.
2. **One home per rule.** Copilot CLI reads `.github/copilot-instructions.md`, `AGENTS.md`,
   `CLAUDE.md`, `.claude/CLAUDE.md`, `GEMINI.md`, and `*.instructions.md` files, plus skills from
   `.github/`, `.claude/`, and `.agents/` directories, **and combines them all**. Duplicated or
   slightly divergent rules across these files are a common source of erratic behavior.
   Pick one file per layer and delete or empty the rest.
3. **Procedures are skills, not instructions.** Anything shaped like "when X, do steps 1–5"
   is a skill; it loads only when relevant.
4. **"Must never" is a hook, not prose.** Instructions are requests the model weighs;
   hooks are enforced by a script before a tool runs.
5. **Add on evidence.** A new rule earns its place after you've made the same correction
   twice. If you can't name the failure a line prevents, delete the line.

## Layout

```
copilot-config/
├── home/                         → installed to ~/.copilot (or $COPILOT_HOME)
│   ├── copilot-instructions.md   personal, always-on, every repo
│   ├── skills/
│   │   ├── handoff/SKILL.md      write NOTES.md before /compact or /clear
│   │   └── resume-task/SKILL.md  re-orient at session start
│   └── hooks/
│       ├── guardrails.json       preToolUse hook registration
│       └── scripts/block-mutations.sh
├── repo-templates/               → copied into a team repo by PR; never installed
│   └── .github/
│       ├── copilot-instructions.md
│       ├── instructions/terraform.instructions.md
│       └── agents/reviewer.agent.md
├── templates/                    → blanks for new skills, instructions, agents
└── scripts/
    ├── install.sh                copy-install home/ (with --dry-run)
    └── audit.sh                  inventory what Copilot will load for a repo
```

Templates live outside any discovered directory on purpose: a template inside
`skills/` or `agents/` would be loaded as a real skill or agent.

## Layers

| Layer | Scope | Loaded | Use for |
|---|---|---|---|
| `~/.copilot/copilot-instructions.md` | You, all repos | Always | Working style, standing rules |
| `.github/copilot-instructions.md` | Team, one repo | Always | Project overview, commands, conventions |
| `.github/instructions/*.instructions.md` | Team, file types | When `applyTo` matches | Language/tool conventions (e.g. Terraform) |
| Skills (`SKILL.md`) | You or team | On demand | Multi-step procedures |
| Custom agents (`.agent.md`) | You or team | When selected / delegated | Narrow roles with restricted tools |
| Hooks (`hooks/*.json`) | You or team | Every matching tool call | Hard guardrails |

## Where does a new thing go?

```
Must it never happen, no matter what?          → hook
Is it a sequence of steps for a situation?     → skill
Does it apply only to certain files?           → *.instructions.md with applyTo
Is it the team's convention for this repo?     → repo copilot-instructions.md (via PR)
Is it how *you* like to work, everywhere?      → personal copilot-instructions.md
Does it need its own tool limits / persona?    → custom agent (rarely)
None of the above / can't name the failure?    → don't add it
```

## Install

```bash
scripts/install.sh --dry-run   # show what would change
scripts/install.sh             # copy home/ into ~/.copilot (existing files backed up)
```

Copy-install, not symlinks: the checkout and the runtime stay independent.
Honors `$COPILOT_HOME` if set.

## Audit

```bash
scripts/audit.sh /path/to/repo
```

Lists every instruction file, skill, agent, hook config, and MCP server Copilot CLI would
see for that repo, with word counts, always-on totals vs. budget, duplicate skill names, and
files pulling in others via `@` includes. Run this first when behavior seems off.

### When behavior is idiosyncratic

1. Run the audit. Check always-on words against budget.
2. Look for the same topic in more than one file, especially `AGENTS.md` and `CLAUDE.md`
   left over from other tools.
3. Look for skills with overlapping descriptions; the model picks between them.
4. Check `/context` in a fresh session to see the real starting load.
5. Remove, don't add. Re-test in a new session after each removal.

## Notes and caveats

- Instruction changes take effect in the **next** session, not the current one.
  After adding a skill mid-session, run `/skills reload`.
- A report on the copilot-cli tracker (issue #3013) says `preToolUse` hooks don't fire for
  subagent tool calls. Until that's confirmed fixed in your version, don't rely on hooks to
  guard `/fleet` subagents.
- Personal `AGENTS.md` loaded via `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` stopped applying
  globally after v1.0.65 (copilot-cli issue #3987). Use `~/.copilot/copilot-instructions.md`.
- Hook payloads come in two formats (camelCase vs. PascalCase event names). The guardrail
  script handles both.
