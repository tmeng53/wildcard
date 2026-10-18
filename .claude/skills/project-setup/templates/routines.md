<!-- Template from engineering-skills/project-setup. Replace <...>, then recreate each routine from a thread ("create a scheduled task that fires into this thread with this prompt and schedule"). Schedules are cron in UTC. Scheduled tasks belong to the account that creates them. -->

# Routines

## PR sweep (hourly)

Start a thread "Keep PRs from getting stuck" and schedule this into it (`53 * * * *`):

```
PR sweep. Goal: no open PR in <repo> sits stuck with nobody on it, and a human hears only what only they can unblock, once each.
Keep a ledger in the project folder (status/pr-sweep.md) of nudges sent, shared blockers and what waits on a human, so nothing is said twice.
Find PRs whose head isn't moving toward merge (red CI, unanswered review, no review or verifier pass, mergeable but not merged) and nudge each one's owner thread once per head, or ask the coordinator to start an owner thread. Report a cause that blocks several PRs to the coordinator once, and decisions waiting on a human for over a day.
Never push, merge or comment on GitHub yourself. End without a reply unless the sweep itself is broken.
```

## Daily brief

Ask the coordinator in the project chat to schedule this daily (`55 12 * * *`):

```
Daily brief for the human, since the last one, under 15 lines and with no internal ids:
what merged, what is in progress and what each waits on, decisions waiting on the human (answerable in a word, linked to their threads), and readiness against the current milestone.
```

## Friction owner (no schedule)

Start a thread "Friction log and synthesis" and tell it:

```
You own design friction. When a thread reports friction, review it against all open friction issues and friction/synthesis.md in the project folder and update the synthesis. Act at once on a recurring or severe theme with a clear fix (a small PR, or an owner thread via the coordinator); otherwise bring it to a human as a decision.
```

Save in project memory that this thread is the friction owner.
