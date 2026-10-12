---
name: handoff
description: Write or update NOTES.md at the repo root so a fresh session can pick up this work. Use before /compact or /clear, at the end of a work block, or when asked for a handoff.
---

# Handoff

Write `NOTES.md` at the repository root. Overwrite it; it describes the current state, not a history.

Use exactly these sections, each a few short bullets:

## Goal
What this work is for, in one or two lines. Link the ticket or PR if there is one.

## Decisions
Choices made and the reason for each. Include rejected options only if someone is likely to re-propose them.

## Done
What is finished and verified. Reference commits or files, not narration.

## Next
The very next concrete step, then the remaining steps in order.

## Gotchas
Exact error strings, version pins, resource addresses, commands that must or must not be run, and anything surprising.

Rules:
- Keep it under 300 words. A new session reads all of it.
- Record facts, not the conversation. No "we discussed" or "I tried".
- Do not include secrets, tokens, account IDs, or credentials.
- After writing, show the file and stop.
