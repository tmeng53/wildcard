---
name: project-setup
description: How to set up a Claude project (a shared space where a coordinating assistant starts one thread per task) so agents work on a repo the way a good engineering team does. Covers project instructions, starter memory, owner threads per PR, review plus independent verification before an agent merges, loud decision requests, the friction loop, and recurring routines. Use when starting a new project, or when an existing one keeps stalling on PRs, decisions or design friction.
---

# Set up a project

A project here is a shared space where a coordinating assistant (the coordinator) answers the project chat and starts one thread per task; threads message each other through it, and all of them share a project folder and memory. A project works when agents behave like a small, well-run team: each piece of work has one owner, nothing merges without someone else checking it, a human is asked only for real decisions and asked clearly, and problems with the design are written down so they add up to a fix. This skill sets that up with three files and a few loops. The repo's own rules stay in its `AGENTS.md` and skills; the project files never repeat them.

## The files

| File | Holds | Where it goes |
| --- | --- | --- |
| [`project-instructions.md`](templates/project-instructions.md) | Purpose and how the assistant works with the people on the project | The project's instructions |
| [`starter-memory.md`](templates/starter-memory.md) | Decisions and facts the repo doesn't record | Pasted into the project chat with "save this as project memory" |
| [`routines.md`](templates/routines.md) | Prompts for recurring tasks and the friction owner | Each recreated from a thread |

Write each with the `agent-instructions` skill: short, true, principles over procedures, "a human" rather than a name.

## The working loops

Each loop is one principle; the templates phrase it for the project.

- **Decisions belong to the right person.** Choices with real trade-offs (contracts, data model, boundaries, new dependencies, user-visible behavior, anything hard to undo) go to a human. Everything else the agent decides, says which default it picked, and keeps going.
- **Decision requests are loud and grounded.** A request gets a reply of its own whose first line marks it as a decision, answerable in a word, with options in plain terms, a recommendation, and credible sources behind it. A decision buried in a file or a long message is a decision nobody sees.
- **Every PR has one owner.** One thread per PR drives it until it merges: it watches its PR, fixes CI and review findings, and pushes only to its own branch. Small PRs from main, never stacked.
- **Nothing merges on the author's word.** A head merges once CI is green, a code review is clean, and a fresh agent that didn't write it has verified that exact head (the `verify-product` skill). When a reviewer is unavailable, a fresh agent stands in under the same rules. The project decides which PRs its agents may merge themselves; the rest wait for a human.
- **Friction is surfaced, not absorbed.** An agent that hits awkward design records it where the team tracks work and works around it minimally. One owner reviews each report against the rest, acts on a recurring theme with a clear fix, and brings the rest to a human.
- **Routines catch what events miss.** A periodic sweep finds stuck PRs and nudges their owners; a daily brief tells a human what merged, what is in progress and what waits on them. A human reads the brief instead of approving each step.
- **Checks run where the agent works.** Cloud sessions start the repo's test services and can't end a turn on red checks (the `cloud-test-environment` skill).
- **General lessons travel.** A rule that would hold in any project also goes to this repo.

## Set it up

1. Prepare the repo: `AGENTS.md` and skills from this repo (see the README), and a `verify-<product>` skill (`verify-product`).
2. Create the project, add the repository, and paste the filled-in project instructions. In the repo, create the `friction` label.
3. Create the cloud environment and add the session hooks (`cloud-test-environment`).
4. Save the starter memory from the project chat.
5. Recreate the routines and name the friction owner (`routines.md`). Schedules are cron in UTC.
6. Try it on one small change: an owner thread opens a PR, a verifier passes it, and it merges by the project's rule. Fix whatever made an agent guess.

## Enforced

Nothing automatic. The daily brief and the PR sweep make a stuck PR, an unanswered decision or a merge without a verdict visible within a day.
