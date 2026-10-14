---
name: onboard-tool
description: Set up a CLI, script, or MCP server for Copilot safely - classify its commands, add cop.psd1 rules, a read-only launcher, and a usage skill. Use when asked to add, integrate, onboard, or set up a tool, let Copilot use it, pre-approve it, or stop it prompting, including tools from someone else's setup. Not for using a tool that's already set up.
---

# Onboard tool

Prevents: a tool approved wholesale that can write or send data elsewhere, an interpreter
(`python`) pre-approved, a credential exposed to Copilot, and approved code that changes
without review.

Run in `cop` (work). Edits under `<COPILOT_HOME>` (`~/.copilot`) and to `cop.psd1` are denied
to your edit tools, so every config write goes through a shell command the user approves.
Gather first, read-only, and don't run the tool yet, not even `--help`:
- The command line that runs it, where its code and dependencies live, who maintains it.
- Its subcommands or MCP tools and flags, from the source.
- How it authenticates, and how large a typical result is.

1. Classify every subcommand and flag as read or write, in a table. A write is anything that
   changes something, writes a file, changes the destination host or tenant, or prints
   credentials or headers (e.g. `--debug`). Unsure means write.
2. The credential must be read by the tool at runtime from Windows Credential Manager or
   `keyring`. An environment variable or plaintext file is readable by commands that run
   without a prompt: stop and say how to move it. Never read, print, or test it yourself.
3. Shared or borrowed code can change after approval. Propose copying it to
   `<COPILOT_HOME>/tools/<name>/`; if it has dependencies, the user installs pinned versions
   into a venv there. Record the source, date, and `Get-FileHash` in a README beside it, and
   rerun this skill when it changes.
4. Propose, and wait for approval:
   - **A launcher that is also the shim**, `<COPILOT_HOME>/bin/<name>.ps1`. It passes only the
     read subcommands, refuses everything else and every write flag, and hard-codes the host
     or tenant. For a script it runs the tool's own interpreter by absolute path
     (`& <venv>/Scripts/python.exe -E -s <script> @args`; `<venv>/bin/python` on macOS or
     Linux, which also need an executable extensionless copy). Never approve an interpreter.
   - **Rule:** `shell(<name>)` in `ReadTools`. For MCP, each tool in `ReadTools` or `ResearchDeny`.
     Writes stay with the user, outside Copilot.
   - **Output limits:** narrow time windows, row limits, or summary formats, in the launcher.
   - **A usage skill**, written with `new-skill`: typical queries, limits, what never to do.
   - **For an MCP server**, no launcher: register it with `copilot mcp add` under the same name
     the rules use.
5. Once approved, draft the launcher, the `cop.psd1` entry (with a comment on why), and the
   usage skill as files in the working folder. Install them with one `Copy-Item` per file
   (for `cop.psd1`, show the full new file first), so each config write is an approval prompt.
   Everything stays local: nothing site-specific goes into copilot-config.
6. Verify, without writing anything real:
   - `cop research --dry-run` lists the rule.
   - `Get-Command <name>` resolves to the launcher, not the original CLI. For MCP, `/mcp show
     <name>` lists the tools the rules name.
   - Read the launcher's refusal branch, then run it with a made-up subcommand and with a
     refused flag: both must refuse.
   - The user starts `cop research` and asks for one typical read: no prompt, reasonable size.

Return the classification table, the files written, and each verification result.

Stop conditions:
- Never test a write against a real system.
- Leave out of `ReadTools` anything you couldn't classify; it prompts.
- A secret would reach Copilot's context: stop and say how to fix it.
