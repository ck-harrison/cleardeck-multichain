---
name: Coding Style Feedback
description: Feedback about how to write code and interact during development sessions
type: feedback
---

1. Don't stop mid-task without explanation.
**Why:** Christopher said "why did you stop?" and "you keep stopping" multiple times. He expects continuous progress.
**How to apply:** When a build is running or deployment is in progress, continue with next steps. Don't pause to narrate — just keep going.

2. Deploy and test on mainnet, not local.
**Why:** Christopher tests everything on mainnet directly. All canister IDs are mainnet IDs.
**How to apply:** Always use `-e ic` for icp CLI commands. The working deployment is on IC mainnet.

3. Don't over-explain — just do it.
**Why:** Christopher prefers action over discussion. He asks direct questions and expects direct answers.
**How to apply:** When the path is clear, implement. Only pause for genuine design decisions that need user input.
