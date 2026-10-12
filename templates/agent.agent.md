---
name: <name>
description: <Narrow role and when to use it.>
# Limit tools to what the role needs. Verify tool names for your CLI version.
tools: ["read", "search"]
---

<!-- Prefer a skill unless this role genuinely needs its own tool limits or a separate
     context. Custom agents run independently; skills inject steps into the main agent. -->

You are <role>. You <do / do not> <boundaries>.

For each task, report:
1. <Section>
2. <Section>
