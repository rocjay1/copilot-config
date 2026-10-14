# Setting up on a new machine

Finishes the setup where the real systems are, for example a Windows work computer. Nothing in
this repo is site-specific; the site-specific part is one local file, `~/.copilot/cop.psd1`.

**You run these steps yourself.** They change Copilot's permission files, your PowerShell
profile, and possibly a security setting, so they shouldn't be delegated to the agent they
configure. It's fine to ask Copilot to explain a step.

Commands are PowerShell 7 (`pwsh`). On Windows, `~` is your profile folder, `C:\Users\<you>`.

## 0. Prerequisites

1. PowerShell 7: `pwsh --version`. The guardrail hook and the test fakes call `pwsh`, so it must
   be on `PATH`. Windows PowerShell 5.1 (`powershell.exe`) is not enough.
2. Copilot CLI, installed the way your company allows (for example
   `npm install -g @github/copilot`; GitHub's install docs list other options), then signed in:
   run `copilot` and follow `/login`.
3. `git`, plus the GitHub CLI signed in: `gh auth login`. The pre-approved PR and run reads use it.
4. Script execution: PowerShell 7 on Windows defaults to `RemoteSigned`, which runs these local
   scripts. Check with `Get-ExecutionPolicy -List`. If a policy is set by your company
   (`MachinePolicy` or `UserPolicy`), don't override it; ask IT. The hook launches with
   `-ExecutionPolicy Bypass`, which a company policy still outranks.

## 1. Back up and retire any previous setup

Copilot CLI combines everything it finds, so leftover skills, agents, hooks, and instructions from
another setup keep firing alongside these.

1. Back up first:
   `Copy-Item -Recurse ~/.copilot "$HOME/.copilot.bak-$(Get-Date -Format yyyyMMdd)"`.
2. Run `./scripts/audit.ps1 <a-work-repo>` and remove anything that isn't from this repo: skills,
   agents, hook configs, and `AGENTS.md` or `CLAUDE.md` files that duplicate instructions.
3. The audit prints saved approvals from `~/.copilot/permissions-config.json`. Remove every entry
   that covers a write (ticket creation, comments, `git push`, `gh pr create`, file writes). A
   saved approval lets that tool run without a prompt in the work profile. Research's deny rules
   still win.

## 2. Install

```powershell
./scripts/install.ps1 -DryRun
./scripts/install.ps1
```

Add the launcher to your PowerShell profile. The profile file often doesn't exist yet,
especially when Documents is synced to OneDrive, so create it first:

```powershell
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Force -Path $PROFILE | Out-Null }
notepad $PROFILE
```

Add this line, then open a new terminal:

```powershell
function cop { & (Join-Path ($env:COPILOT_HOME ?? "$([Environment]::GetFolderPath('UserProfile'))/.copilot") 'bin/cop.ps1') @args }
```

Keep `NOTES.md` (written by `handoff`) out of every repo's commits by adding it to your global
git ignore file. This uses the existing file if you have one:

```powershell
$ignore = git config --global --get core.excludesFile
if (-not $ignore) {
    $ignore = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.gitignore_global'
    git config --global core.excludesFile $ignore
}
$ignore = $ignore -replace '^~', [Environment]::GetFolderPath('UserProfile')
if (-not (Select-String -Path $ignore -Pattern '^NOTES\.md$' -Quiet -ErrorAction SilentlyContinue)) {
    Add-Content -Path $ignore -Value 'NOTES.md'
}
```

An ignored `NOTES.md` exists only on that machine, in that worktree. Removing the worktree
removes the notes.

## 3. Write `~/.copilot/cop.psd1`

1. `Copy-Item templates/cop.psd1.example ~/.copilot/cop.psd1`
2. Connect Atlassian's MCP server under the name the template uses:

   ```powershell
   copilot mcp add --transport http atlassian https://mcp.atlassian.com/v2/mcp
   ```

   Atlassian's sign-in and consent page opens in your browser on its own, before you start a
   session (seen on 1.0.97). Approve access to your site. If it doesn't open, start `cop`, run
   `/mcp`, and authenticate `atlassian` from there. Your Atlassian admin can restrict MCP access; if sign-in is
   refused, ask them. Calls draw on your organization's Rovo credits.
3. Run `/mcp show atlassian` and compare its tools with the template. The template's names were
   checked on 1.0.97 against the v2 endpoint. If Atlassian has added tools, sort them into
   `ReadTools` (reads only) or `ResearchDeny` (anything that creates, edits, transitions,
   comments, or deletes). When unsure, leave a tool out; it will prompt.

   v2 routes most operations through `discover` plus `executeRead`, `executeWrite`, and
   `executeDestructive`. Only `executeRead` is pre-approved. That's safe because Atlassian's
   server enforces the split: a write operation sent through `executeRead` is refused with a 403
   (checked on a test site).
4. Add your other CLIs, e.g. the Dynatrace CLI, following the comments in the template. Copilot
   approves a CLI as a whole, not per subcommand, so a CLI that can write needs a read-only shim.
5. Check the result: `cop research --dry-run` lists every allow and deny flag.

## 4. Verify

1. Offline checks, free: `./tests/cop.ps1` and `./tests/hook.ps1`. Both should report all cases
   passed.
2. `./tests/smoke.ps1`: live permission checks against fakes, about 13 premium requests. It
   touches nothing real. **All cases must PASS, including H1** (the guardrail hook): on Windows,
   Copilot runs shell commands through PowerShell, and both the permission patterns and the hook
   were first verified on macOS. If a case fails, check its `out.jsonl` under the scratch
   directory the test prints, and don't rely on that protection until it passes.
3. With the real names, **reads only**:
   - `cop research`, then ask for a Jira search. It should run without a prompt.
   - `cop`, then ask for the same search. It should run without a prompt.
4. Don't test writes against real systems. The smoke test already showed that writes prompt in
   `work` and are denied in `research`. If a real write ever runs without a prompt, stop and check
   `permissions-config.json` and `cop.psd1`.

## 5. Trial ticket

Work one real ticket end to end: `cop research` to investigate, then `cop` with `work-ticket`.
Review each batch, open the PR yourself (or approve the prompt), and let Copilot review it.

It worked if:
- nothing outside your machine changed without your approval;
- you can explain every line of the PR;
- you didn't lose track of the work across a `/clear`;
- it wasn't noticeably slower than before.

Afterwards, add to `ReadTools` only the reads that actually prompted and annoyed you.
