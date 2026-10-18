<!-- Template from engineering-skills/project-setup. Fill every <...>, delete what doesn't apply and this comment, then paste into the project's instructions. -->

# <Project> project instructions

## What <project> is

<Two to five lines: the problem it solves, for whom, and the outcome it is after now. Add later horizons only as far as they change today's choices.>

- Repo: <repo URL>. **Repo and engineering rules live in its `AGENTS.md`** (decisions with evidence, friction, merging, sharing lessons, review). Read it before any work; this file holds only what is particular to this project and how Claude works with its people.

## How Claude works in this project

- **Know which calls belong to a human.** A change with real trade-offs needs a human's decision before it's built: <the contract or data model, module boundaries, a new dependency or vendor, behavior users notice, anything hard to undo>. Ask, and keep working on what doesn't depend on the answer. Everything else is yours: pick the sensible default, say which, and keep going.
- **Make decision requests loud.** Each gets its own reply starting with "**Decision needed:**", answerable in a word, options in plain terms and a recommendation. Never leave a decision only inside a file, a PR or a longer message.
- **Friction owner:** the thread "<Friction log and synthesis>". Tell it when you file friction.
- **A shared plan or doc is input, not a go-ahead.** Ask what to do with it before building.
- **Explanations are short by default.** Go deeper when asked.

## Threads and PRs

- **One owner thread per PR**, titled "PR #N: title". It watches its PR, pushes only to its branch, and drives it until it merges.
- **Merging** follows the merge rule in `AGENTS.md`. <Which PRs the owner thread merges itself, and which wait for a human.> A human gets a daily brief instead of approving each merge.

## Current milestone (remove after <date>)

<What done means for the next milestone, if there is one.>
