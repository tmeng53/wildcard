---
name: wildcard-docs
description: How agents working on Wildcard coordinate. Work is coordinated in the Claude project the agent runs in; GitHub issues and PRs carry work items, bugs, code and anything another developer's agents need. Escalate disagreements to a human. Use at the start of every session in this repo and whenever a decision, scope or work-item status changes.
---

# Wildcard: coordinating work

Wildcard is one codebase. Several agents may work on it at once, each on its own branch and PR.

## Where things go

| Where | Use it for |
| --- | --- |
| **The Claude project** you run in | Your own work: questions, status, handoffs, screenshots and decisions with the people and agents in that project. One thread owns each PR |
| **GitHub issue** | One per work item, bugs, friction, and anything you need from another developer or their agents |
| **GitHub PR** | All code. Review comments, verifier verdicts and any contract change happen here |

Don't duplicate: if it's about an issue or PR, comment there and link it elsewhere.

No GitHub access? Tell the human what you would have posted.

## Check for updates

At the start of a session, and before you start or finish a work item, check GitHub: new comments, reviews and CI on your PRs, issues assigned to you, and open issues labelled `needs-human`. Answer anything addressed to you.

## GitHub conventions

- **Labels:** `contract`, `needs-human`, `friction` (design friction, see AGENTS.md).
- **Issues:** an imperative title. Link the plan or brief; don't copy it. An issue for another developer's agents says what you need, why, and what it unblocks, and assigns or mentions that developer.
- **Branches** come from `main`, one per PR. **PR titles** as in the `raise-pr` skill, with `Closes #<issue>` in the body.
- **Contract changes** (`ios/Packages/Contracts`, database migrations, the API): label `contract` and request review from a code owner (`.github/CODEOWNERS`). If the change breaks other code, fix the callers in the same PR or say exactly what they need to change.

## When agents can't agree

After one round of replies, post where the discussion is (PR, issue or project thread), starting with **Decision needed:**, answerable in a word, with each option in plain terms and your recommendation:

> **Decision needed:** Store check-in photos in Supabase Storage or on a CDN? Option 1: Supabase Storage, one vendor, simplest. Option 2: Cloudflare R2, cheaper at scale. I recommend 1 for the MVP.

On GitHub, also add the `needs-human` label. Stop work on that point (keep working on anything else) until a human answers, then follow it and remove the label.
