# copilot-config

A minimal, auditable framework for GitHub Copilot CLI configuration.

The goal is the **least** configuration that produces predictable behavior. Every line of
always-on context is paid for in every session and competes with every other line, so this
repo is built around keeping that surface small and putting each rule in exactly one place.

## Principles

1. **Small always-on budget.** Instruction files load into every session. This repo uses
   personal ≤ 300 words and repo root ≤ 500 words as review heuristics; they are not GitHub
   limits. `scripts/audit.sh` checks these project budgets.
2. **One home per rule.** Copilot CLI reads `.github/copilot-instructions.md`, `AGENTS.md`,
   `CLAUDE.md`, `.claude/CLAUDE.md`, `GEMINI.md`, and `*.instructions.md` files, plus skills from
   `.github/`, `.claude/`, and `.agents/` directories, **and combines them all**. Duplicated or
   slightly divergent rules across these files are a common source of erratic behavior.
   Pick one file per layer and delete or empty the rest.
3. **Procedures are skills, not instructions.** Anything shaped like "when X, do steps 1–5"
   is a skill; it loads only when relevant.
4. **Hooks are guardrails, not guarantees.** A hook can automatically block known patterns
   before a tool runs, but is not a security boundary; pair it with permissions, sandboxing,
   and narrowly scoped credentials for unacceptable side effects.
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
| Hooks (`hooks/*.json`) | You or team | Every matching tool call | Automated guardrails |

## Where does a new thing go?

```
Could this cause an unacceptable side effect?  → hook plus independent controls
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
files pulling in others via `@` includes. This is an inventory and estimate, not a substitute
for checking what the CLI actually loaded. Run this first when behavior seems off.

### When behavior is idiosyncratic

1. Run the audit. Check always-on words against this repo's heuristic budgets.
2. Look for the same topic in more than one file, especially `AGENTS.md` and `CLAUDE.md`
   left over from other tools.
3. Look for skills with overlapping descriptions; the model picks between them.
4. Check `/instructions` and `/context` in a fresh session to see which instructions loaded
   and the real starting context.
5. Remove, don't add. Re-test in a new session after each removal.

## Notes and caveats

- This repository targets **Copilot CLI**. Configuration discovery, hook behavior, and
  supported frontmatter can differ in Copilot cloud agent and IDEs; verify each artifact
  against the documentation for the surface and CLI version you use.
- The guardrail hook is a best-effort pattern blocklist, not a security boundary. It catches
  common mutating Terraform, AWS, kubectl, and Helm commands, but a command written in an
  unexpected form, or run through a script or another tool, can get past it. It has not yet
  been verified in a live Copilot CLI session. Keep real credentials scoped so that the
  agent can't make changes even if the hook misses one.
- Before relying on the hook, test representative blocked commands, safe commands that should
  remain allowed, and likely bypass forms in a disposable environment. Verify whether hooks
  run for subagent calls in your CLI version; do not treat a successful top-level test as
  coverage for subagents.
- The audit's file inventory and word counts are approximate. Compare its findings with
  `/instructions` and `/context` in a fresh session, especially after CLI upgrades.
- Instruction changes take effect in the **next** session, not the current one.
  After adding a skill mid-session, run `/skills reload`.
- Older Copilot CLI releases were affected by issue #3013, where `preToolUse` and `postToolUse`
  hooks didn't apply to subagent calls. Current releases include the fix; update your CLI and
  test your installed version before relying on hooks to guard `/fleet` subagents.
- Personal `AGENTS.md` loaded via `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` stopped applying
  globally after v1.0.65 (copilot-cli issue #3987). Use `~/.copilot/copilot-instructions.md`.
- Hook payloads come in two formats (camelCase vs. PascalCase event names). The guardrail
  script handles both.
