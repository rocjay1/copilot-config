# copilot-config

A minimal, auditable framework for GitHub Copilot CLI configuration.

The goal is the **least** configuration that produces predictable behavior. Every line of
always-on context is paid for in every session and competes with every other line, so this
repo is built around keeping that surface small and putting each rule in exactly one place.

## Principles

1. **Small always-on budget.** Instruction files load into every session. This repo uses
   personal ≤ 300 words and repo root ≤ 500 words as review heuristics; they are not GitHub
   limits. `scripts/audit.ps1` checks these project budgets.
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
├── home/                         → installed to ~/.copilot (or $env:COPILOT_HOME)
│   ├── copilot-instructions.md   personal, always-on, every repo
│   ├── bin/cop.ps1               launcher with work / research permission profiles
│   ├── skills/
│   │   ├── work-ticket/SKILL.md  ticket → plan → reviewable batches → PR description in chat
│   │   ├── pr-review/SKILL.md    triage review threads → fix → reply, resolve, re-request
│   │   ├── handoff/SKILL.md      write NOTES.md before /compact or /clear
│   │   └── resume-task/SKILL.md  re-orient at session start
│   └── hooks/
│       ├── guardrails.json       preToolUse hook registration
│       └── scripts/block-mutations.ps1
├── repo-templates/               → copied into a team repo by PR; never installed
│   └── .github/
│       ├── copilot-instructions.md
│       ├── instructions/terraform.instructions.md
│       └── agents/reviewer.agent.md
├── templates/                    → blanks for new skills, instructions, agents, cop.psd1
├── tests/                       → smoke.ps1 (live), hook.ps1 and cop.ps1 (offline)
├── docs/setup-at-work.md         → finish setup on a machine with the real systems
└── scripts/
    ├── install.ps1               copy-install home/ (with -DryRun)
    └── audit.ps1                 inventory what Copilot will load for a repo
```

All scripts are PowerShell 7 (`pwsh`) and run on Windows, macOS, and Linux.

Templates live outside any discovered directory on purpose: a template inside
`skills/` or `agents/` would be loaded as a real skill or agent.

## Control model

Autonomy is set by side effect, not by task:

| Tier | Examples | Behavior |
|---|---|---|
| Read | Jira/Confluence reads, `gh pr view`, `git log`, `cat`/`grep`, monitoring CLIs | Pre-approved: runs freely |
| Local write | File edits in the working folder | Pre-approved in `cop`; planned first, then small batches whose diffs you review (personal instructions) |
| External write | Tickets, comments, PRs, `git push`, branches, worktrees | One at a time, only when asked, with a prompt every time |

`cop` makes this concrete. Allow and deny flags aren't saved between sessions, so it's the one
place the policy lives:

```powershell
cop research   # reads pre-approved; file edits and listed external writes denied
cop            # (work) reads and local edits pre-approved; external writes prompt
cop --dry-run  # print the exact copilot command and flags
cop --check-notes   # is NOTES.md current with the uncommitted work?
```

Site-specific tools (your MCP servers and CLIs) go in `~/.copilot/cop.psd1`, a data file that is
never committed. Start from `templates/cop.psd1.example`. `cop` refuses `--yolo`, `--allow-all*`,
`--assisted-approval`, and autopilot, and ignores the environment variables that do the same.

Research is not a sandbox: any shell command that isn't pre-approved or denied still prompts,
so read what you approve there too.

A prompt in `cop` means something outside your machine, or an unlisted command. Don't switch
to `/permissions allow-all`, `/permissions assisted`, or `/autopilot on` in a work session:
they remove those prompts and the stops between batches. Research's deny rules and the
guardrail hook still hold in any mode. If a harmless command keeps prompting, add it to
`ReadTools` in `cop.psd1` instead.

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

```powershell
./scripts/install.ps1 -DryRun   # show what would change
./scripts/install.ps1           # copy home/ into ~/.copilot (existing files backed up)
```

Copy-install, not symlinks: the checkout and the runtime stay independent.
Honors `$env:COPILOT_HOME` if set. Then add the launcher to your PowerShell profile
(`notepad $PROFILE`; see [docs/setup-at-work.md](docs/setup-at-work.md) if the file doesn't exist yet):

```powershell
function cop { & (Join-Path ($env:COPILOT_HOME ?? "$([Environment]::GetFolderPath('UserProfile'))/.copilot") 'bin/cop.ps1') @args }
```

On a machine with real systems to connect, continue with
[docs/setup-at-work.md](docs/setup-at-work.md).

## Test

```powershell
./tests/cop.ps1            # launcher checks, offline
./tests/hook.ps1           # guardrail hook against ~50 commands, offline
./tests/smoke.ps1          # live Copilot sessions, ~17 premium requests
./tests/smoke.ps1 W2 R2    # selected live cases
```

CI (`.github/workflows/tests.yml`) runs the two offline tests on Windows and macOS for every PR
and push to `main`.

The smoke test runs real Copilot CLI sessions against a fake MCP server, a fake CLI, and a local git remote, in
an isolated `COPILOT_HOME`. It checks that reads run, writes prompt in work and are denied in
research, and that the guardrail hook blocks `terraform apply`. Run it on every new machine
(Windows runs shell commands through PowerShell, which can differ from macOS) and again after
`copilot update`.

## Audit

```powershell
./scripts/audit.ps1 /path/to/repo
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
  unexpected form, or run through a script or another tool, can get past it. Verified in
  Copilot CLI 1.0.97 as a user-level hook (`tests/smoke.ps1` H1). It starts `pwsh`, so it
  needs PowerShell 7 on `PATH`; a hook that times out fails open (the call goes through the
  normal permission flow). Keep real credentials scoped so that the agent can't make changes
  even if the hook misses one.
- Repository hooks (`.github/hooks/`) did not fire in a folder Copilot hadn't been told to
  trust (1.0.97, `-p` mode). Don't count on a repo's own hooks until you've trusted the folder
  and seen them fire.
- In 1.0.97, a preToolUse hook that answers "allow" **overrides deny rules**, and approves the
  whole command line, including anything chained after `&&`. So no hook here ever answers
  "allow", and any hook that does (for example, one left over from another setup) quietly
  undoes research's denies. Read every hook `scripts/audit.ps1` lists.
- In 1.0.97, a `write` approval also covers shell redirection (`cmd > file`) inside the working
  folder, despite what `copilot help permissions` says. It doesn't approve the command itself
  or a path outside the folder (`tests/smoke.ps1` W9, W10). Recheck after `copilot update`.
- For CLIs other than `git` and `gh`, `shell(...)` patterns match the command name only:
  `shell(mycli)` approves every subcommand, and `shell(mycli get)` matches nothing. To
  pre-approve reads from a CLI that can also write, approve a read-only shim
  (see `templates/cop.psd1.example`).
- Before relying on the hook, test representative blocked commands, safe commands that should
  remain allowed, and likely bypass forms in a disposable environment; `tests/hook.ps1` and
  `tests/smoke.ps1` do this. Verify whether hooks run for subagent calls in your CLI version;
  do not treat a successful top-level test as coverage for subagents.
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
