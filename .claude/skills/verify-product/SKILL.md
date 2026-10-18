---
name: verify-product
description: How to give a project a `verify-<product>` skill, so an agent that did not write a change runs the product end to end, checks the evidence at its source, and gives a PASS, PASS+NOTES or FAIL verdict tied to the exact commit and diff. Use when setting up a project for independent verification, when adding a user journey the verifier should drive, and when asked to verify another agent's change.
---

# Verify the product

Green CI and a review bot are not proof that a change works. A verifier is an agent that did not write the change. It runs the product the way its users do, reads the real output, checks the evidence itself, and gives a verdict tied to the exact code it ran. Each project writes down how to do that in its own skill, `verify-<product>`, from `templates/.claude/skills/verify-project/`.

## The rules every verifier follows

- **Verify, never fix.** Don't edit the code under test to make it pass. A problem you find is a FAIL with evidence; the author fixes it.
- **One verdict per diff.** A verdict names the commit and a hash of its exact diff. A push that changes the diff needs a new verdict; merging main in without changing the PR's own diff keeps it.
- **Check evidence at its source.** A script printing "paid" is a claim. The external system's record, the signature and the database row are the evidence.
- **Inconclusive is FAIL.** If a step can't run (no Docker, a service won't start), the verdict is FAIL with the reason. Never skip or fake a step.
- **Judge the change, not the history.** A problem the change brings in is a FAIL. A problem already on main that the change doesn't touch goes in Notes.

## What the project's skill holds

Copy the template and fill in every `<...>`. It has these sections, in order:

1. **Pin what you verify.** A detached checkout of the PR's head in its own worktree (`git worktree add --detach <dir> origin/<branch>`, so the author's checkout stays untouched), a clean tree (`git status --porcelain` prints nothing), dependencies reinstalled from the lockfile (not the ones installed at session start), the full sha, and the diff hash. Flag it when the branch is behind main. Hash the diff after fetching main into `origin/main` with an explicit refspec (a bare `git fetch origin main` leaves `origin/main` stale in clones without a fetch refspec), so a merged-in main isn't counted as part of it. Verifying main itself gives the empty diff, `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`:

   ```sh
   git fetch origin +refs/heads/main:refs/remotes/origin/main && git diff --full-index --binary origin/main...HEAD | sha256sum | cut -d' ' -f1
   ```

   Hash the exact diff, not `git patch-id`: patch ids ignore line numbers and (without `--verbatim`) whitespace, so two different changes can share one. `--full-index --binary` makes the diff cover binary files and full blob ids.
2. **An evidence folder** outside the repo, keyed by short sha, so it survives cleanup. Write it as a literal path (`/tmp/verify-<product>/<short sha>`) in every command, never as a variable: an agent's shell often loses variables between separate commands.
3. **Launch.** The exact commands that bring the stack up, on a laptop and in a cloud session (the `cloud-test-environment` skill in this repo sets up the session-start hook). If a stack is already running, reuse it and record that you didn't start it: a fixed compose project name means two checkouts share one stack.
4. **Health check.** Each command and what "healthy" prints, copied from a real run. If the stack won't start, the verdict is FAIL, with its logs saved as evidence.
5. **Journeys.** A table of `features/` files, one per thing a user does, each **Ready**, **On main, not drivable** (with the reason, such as no documented local setup), or **Not on main yet**. The verifier runs every journey the change touches plus every Ready one (it is cheap and catches breakage the author didn't expect).
6. **Evidence.** One row per kind of evidence the product produces (external system state, signatures, database rows, what a user or agent sees), each with the query or command that checks it and the exact fields that must match (for example the record's `status`, the exact `amount`, the result code). Leave out kinds no journey produces yet.
7. **A probe.** At least one thing the author may not have tried: an edge case, a wrong input, a repeat of the same call.
8. **Cleanup.** Stop only what you started, item by item: servers and watchers, the stack and a Docker daemon if you started them, the worktree. Keep data volumes. Never wipe a shared stack or a database you didn't create. The evidence folder stays.
9. **The verdict.** PASS, PASS+NOTES or FAIL, in a fixed template: commit, diff hash, journeys run, journeys not run and why, real quoted output lines (never paraphrased), and notes. Post it where the change is discussed (the PR; without one, where the verdict was asked for, and a copy in the evidence folder), and never edit a verdict after posting it.

## A journey file

Each file in `features/` (`templates/.claude/skills/verify-project/features/journey.md`) covers one user journey:

- **Status:** Ready; On main, not drivable (and why); or Not on main yet (with the PR expected to land it).
- **Drive it:** the commands, starting from an empty stack.
- **Expected output:** its shape, since ids and times change between runs. Anything else is a FAIL.
- **Evidence:** what to check and where, pointing to the evidence table.
- **Worth probing:** the edge cases most likely to break.

The PR that adds a journey fills in its file and sets its row to Ready. A journey that isn't on main yet but is in the change under test is driven from the PR's own docs and tests, and the verdict notes that its file needs filling in.

## Validate the skill cold

While writing the skill, run every command in it and paste the real output: a guessed expected value is usually wrong. Then, before relying on it, have a fresh agent with no context follow it on a real change. Every place the agent had to guess (a missing command, an unstated expected value, a path it had to look up) is a gap: fix it in the skill and run again until it doesn't guess. Repeat after changing the stack.

## Enforced

Nothing automatic yet. The verdict template makes a missing commit, diff hash or quoted evidence visible: a verdict without them doesn't count. The project's `raise-pr` and PR template can require a verdict before a human merges.
