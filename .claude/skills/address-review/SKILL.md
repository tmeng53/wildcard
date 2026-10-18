---
name: address-review
description: How to respond to code review findings, from people or review bots, without turning a PR into a pile of patches. The one place for the review-reply workflow. Use whenever a PR you own gets review comments, and before pushing a second or later round of review fixes.
---

# Address review feedback

A review finding is a symptom. Fixing each comment where it points tends to leave a PR patchier after every round; fixing what caused it often clears several findings at once and the next round's too.

## For each finding

1. **Check it's real.** Trace a realistic path from a real caller or input to the failure. If there is none, reply on the thread with the path you checked and why no change is needed.
2. **Ask what design causes it.** Is it one instance of a pattern (a missing type, a check in the wrong layer, two sources of truth, an unclear name)? Look for the other instances in the PR.
3. **Fix the cause, not the line.** Prefer the change that removes the whole class of finding: a type that makes the bad state unrepresentable, moving the check to the one place it belongs, deleting the duplicate. One change that fixes three findings beats three patches.
4. **Reply on each thread** with the commit and the proof it works (the command you ran and what it printed), or with a concrete reason when you change nothing.
5. **Re-run the checks** before pushing, and update the PR's Verification section if the evidence changed.

## After one or two rounds: re-synthesize

Step back and reread the whole change as if you were seeing it for the first time.

- Is it still the simplest design that meets the need? Or has it grown special cases, flags and guards one finding at a time?
- If it has become patchy, rework it from first principles into the simplest design, even if that means rewriting what earlier rounds added. Say in the PR what changed and why.
- Update the PR description so it describes the change as it is now, not as it started.

## When in doubt, ask the owner

Ask before acting when a finding asks for a different design, changes behavior users see, or conflicts with a decision already made. Give the options and your recommendation, one line each.

## Enforced

No check. A reviewer asks "would one design change have fixed these?" when the same kind of finding appears twice.
