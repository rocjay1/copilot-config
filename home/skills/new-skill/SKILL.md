---
name: new-skill
description: Create a new Copilot skill, or revise one, to this setup's standard - usually from a procedure that just worked in this session. Use when asked to make, save, or turn something into a skill, or to fix a skill that didn't trigger or misbehaved. Not for running a skill.
---

# New skill

Prevents: skills that never trigger, run past their purpose, write to external systems
unasked, or grow into prose nobody maintains.

Gather first:
- The procedure: what actually worked in this session (not the dead ends), or the user's steps.
- The failure it prevents, in one sentence. If nobody can name one, stop: it isn't worth a skill.
- Existing skills: personal ones in `<COPILOT_HOME>/skills/` (`$env:COPILOT_HOME`, or
  `~/.copilot`), `~/.claude/skills/`, and `~/.agents/skills/`; the repo's `.github/skills/`,
  `.claude/skills/`, and `.agents/skills/`. Read any that overlap; extending one beats adding another.

1. Check it belongs in a skill. A rule that always applies is an instructions line; a side
   effect that must never happen needs a deny rule or hook; a one-off needs nothing. If it
   isn't a skill, say what it is instead and stop.
2. Propose, and wait for approval:
   - **Name:** lowercase-hyphenated, named for the task (`cab-draft`, not `helper`).
   - **Location:** `<COPILOT_HOME>/skills/<name>/SKILL.md` for personal or site-specific skills
     (it stays on this machine; `install.ps1` never touches it), or `.github/skills/<name>/`
     in a team repo, by PR.
   - **Description:** what it does, then "Use when ..." with the phrases the user would
     actually say, then "Not for ..." if a nearby request could match by mistake. Copilot
     picks skills by this line alone.
   - An outline of the steps.
3. Write it in this shape, under about 450 words:
   - frontmatter: `name` (same as the folder) and `description`;
   - `# Title`, then `Prevents: <the failure>`;
   - `Gather first:` the inputs, read-only;
   - numbered steps, one action each, with exact commands where they matter and where it
     stops for approval;
   - what it returns, and in what shape;
   - `Stop conditions:` when to stop and report instead.
4. Build in the safety rules:
   - External systems stay read-only unless the user asks for that specific write. A skill
     that drafts a ticket, CAB request, comment, or PR puts the text in chat or a local file
     and never submits it.
   - Name the commands it runs. Don't route around prompts or research's deny rules.
   - No credentials, tokens, or site URLs. Site-specific names belong only in local skills or
     `cop.psd1`.
5. Show the file and wait. Once approved, write it. For a personal skill your edit tools are
   denied under `<COPILOT_HOME>`: draft it in the working folder, then install it with
   `New-Item -ItemType Directory -Force` and `Copy-Item`, which the user approves. Tell them
   how to test it: new session (or `/skills reload`), ask for the task in their own words
   without naming the skill, and check it loads. If it doesn't, fix the description, not the steps.

Stop conditions:
- Over about 450 words, or more than one task: propose splitting it.
- Don't edit skills installed from copilot-config (`work-ticket`, `pr-review`, `handoff`,
  `resume-task`, `friction-log`, `new-skill`, `onboard-tool`) in `<COPILOT_HOME>/skills`; the
  next install overwrites them. Change those in the copilot-config repo by PR.
