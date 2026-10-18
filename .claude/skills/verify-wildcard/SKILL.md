---
name: verify-wildcard
description: How an agent that did not write a change proves Wildcard works end to end (the iOS app in the simulator on the self-hosted Mac, local Supabase in Docker), checks the evidence (simulator screenshots, database rows) and gives a PASS, PASS+NOTES or FAIL verdict tied to the exact commit and diff. Use when asked to verify a PR, branch or commit, or to give a verdict on another agent's change.
---

<!-- From engineering-skills/verify-product. Sections 2, 3 and 5 are filled in by the PR that adds the Xcode project and the first Supabase migration; until then a verifier drives each change from its PR's own docs and tests. -->

# Verify Wildcard

You are the verifier. You did not write the change, and your verdict is the only thing that says it works: green CI and a review bot are not verdicts. Run wildcard the way its users do, read the real output, and check the evidence yourself instead of trusting what the author or a script says.

## Rules

- **Verify, never fix.** Don't edit the code under test to make it pass. A problem you find is a FAIL with evidence; the author fixes it.
- **One verdict per diff.** A verdict covers one commit and the hash of its exact diff. A push that changes the diff needs a new verdict; merging main in without changing the PR's own diff keeps it.
- **Check the evidence at the source.** A script printing a success line is a claim. The simulator screenshot and the database row are the evidence.
- **Inconclusive is FAIL.** If a step can't run (no Docker, a service won't start), the verdict is FAIL with the reason. Never skip or fake a step.
- **Judge the change, not the history.** A problem the change brings in is a FAIL. A problem already on main that the change doesn't touch goes in Notes, with a link to an issue if one exists.

## 1. Pin what you are verifying

```sh
git fetch origin +refs/heads/main:refs/remotes/origin/main +refs/heads/<branch>:refs/remotes/origin/<branch>   # explicit refspecs, so origin/* is never stale
git worktree add --detach /tmp/verify-wildcard/tree-<short sha> origin/<branch>   # the PR's head, leaving your checkout alone
cd /tmp/verify-wildcard/tree-<short sha>
git status --porcelain                      # must print nothing: verify committed code only
swift package resolve --package-path ios/Packages/<Package>   # and pnpm --dir web install --frozen-lockfile once web/ exists
git rev-parse HEAD                          # the commit the verdict names
git diff --full-index --binary origin/main...HEAD | sha256sum | cut -d' ' -f1   # the diff the verdict covers; main itself gives e3b0c442…7852b855 (empty)
git merge-base --is-ancestor origin/main HEAD || echo "behind main"
```

If the branch is behind main, say so in Notes: the author merges main in, and a new verdict follows if the diff changed.

Read the PR description (if there is no PR, the request that asked for the verdict) and the diff to decide which journeys in `features/` it touches. Always run every journey marked **Ready**.

Keep evidence in one folder outside the repo, so it survives cleanup. Shell variables don't survive between an agent's separate commands, so write the literal path, with the real short sha, in every command (below: `/tmp/verify-wildcard/<short sha>`):

```sh
mkdir -p /tmp/verify-wildcard/$(git rev-parse --short HEAD)
```

## 2. Launch the stack

<In a cloud session, what the session-start hook already did and the line it prints.> If the stack is already running, reuse it and note in the verdict that you didn't start it. Otherwise:

```sh
<install command>
<env file setup>
<start command, e.g. docker compose up -d --wait --wait-timeout 120>
```

## 3. Health check

All must pass before you drive anything (the expected values come from a real run):

```sh
<command>    # <what healthy prints>
<command>    # <what healthy prints>
```

If a service won't start, stop: the verdict is FAIL, reason "stack did not start", with `<logs command>` saved to `/tmp/verify-wildcard/<short sha>/`.

## 4. Drive the journeys

Each file in [`features/`](features/) is one thing a user does: how to drive it, the expected output, and which evidence to check.

| Journey | Status |
| --- | --- |
| Daily check-in: pick 练了 / 吃得干净 / 今日免责声明 and see it on the squad track | Not on main yet |
| Join a squad from an invite link | Not on main yet |
| Sunday 战报 recap | Not on main yet |
| Weekly schedule poster (3:4) | Not on main yet |

A journey that isn't on main yet but is in the change under test: drive it the way the PR's own docs and tests describe, check the evidence listed in its file, and note in the verdict that its feature file needs filling in.

Save each command's full output (`... 2>&1 | tee /tmp/verify-wildcard/<short sha>/<journey>.log`).

## 5. Check the evidence

Every journey ends with evidence you read yourself. Keep only the kinds a journey produces:

| Evidence | How to check it |
| --- | --- |
| **<External system state>** | <query against the system itself>; <each field and its value, e.g. `status` is `<X>`, result `<success code>`, amount exactly `<n>`> |
| **<Signatures>** | <verify with the public key; changing one byte must make it fail> |
| **<Database rows>** | <psql command>; the rows exist, and nothing immutable was edited or deleted |
| **What a user or agent sees** | <no internal error messages or internals in public-facing copy> |

Then try at least one thing the author may not have: the change's edge case, a wrong input, or a repeat of the same call. wildcard must refuse what it says it refuses.

## 6. Clean up

Stop only what you started: servers and watchers; the stack (`<stop command>`, which keeps data volumes) and a Docker daemon, if you started them; and the worktree (`git worktree remove /tmp/verify-wildcard/tree-<short sha>`). A stack you found running stays running; never wipe a stack or database you didn't create. The evidence folder stays.

## 7. The verdict

Post it where the change is discussed: as a PR comment when there is a PR, else where the verdict was asked for. Save a copy as `/tmp/verify-wildcard/<short sha>/verdict.md`. Never edit it after posting. Exactly one of:

- **PASS**: every journey you ran did what it should, and the evidence matches.
- **PASS+NOTES**: it works, with issues that don't block (each one named).
- **FAIL**: something didn't work, or couldn't be checked. Name the first failing step and its output.

```md
**Verdict: PASS** (verify-wildcard)

- Commit: `<full sha>`
- Diff: `<sha256 of the diff>`
- Journeys: <journey> (Ready); <which journeys this change touches>
- Not run: <journey>, because <reason>; or none
- Evidence:
  - `<command>`: `<quoted output line>`
  - <evidence kind>: <what you read at the source>
  - extra check: `<what you tried>` → `<what happened>`
- Notes: none
```

Quote real output lines, never paraphrase them. A verdict without a commit, a diff hash or evidence doesn't count.

## Keeping this skill current

The PR that adds something a user can do adds or fills in its file in `features/` and sets its row above to **Ready**. Changes to this skill are agent rules, so a human merges them.
