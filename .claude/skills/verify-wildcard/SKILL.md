---
name: verify-wildcard
description: How an agent that did not write a change proves Wildcard works end to end (the iOS app through the simulator screenshots and UI-test results CI's macOS job uploads, local Supabase in Docker), checks the evidence (simulator screenshots, database rows) and gives a PASS, PASS+NOTES or FAIL verdict tied to the exact commit and diff. Use when asked to verify a PR, branch or commit, or to give a verdict on another agent's change.
---

<!-- From engineering-skills/verify-product. Sections 2, 3 and 5 cover local Supabase (filled in with the first migration); the iOS parts are filled in by the PR that adds the Xcode project. -->

# Verify Wildcard

This skill says how to run Wildcard and check its evidence. The verification process itself (who starts the verifier, the clean checkout, one verdict comment per PR, re-runs) is in `raise-pr` (Independent verification); where they differ, `raise-pr` wins.

You are the verifier. You did not write the change, and your verdict is the only thing that says it works: green CI and a review bot are not verdicts. Run wildcard the way its users do, read the real output, and check the evidence yourself instead of trusting what the author or a script says.

## Rules

- **Verify, never fix.** Don't edit the code under test to make it pass. A problem you find is a FAIL with evidence; the author fixes it.
- **One verdict per diff.** A verdict covers one commit and the hash of its exact diff. A push that changes the diff needs a new verdict; merging main in without changing the PR's own diff keeps it.
- **Check the evidence at the source.** A script printing a success line is a claim. The simulator screenshot and the database row are the evidence.
- **Inconclusive is FAIL.** If a step can't run (no Docker, a service won't start), the verdict is FAIL with the reason. Never skip or fake a step.
- **Judge the change, not the history.** A problem the change brings in is a FAIL. A problem already on main that the change doesn't touch goes in Notes, with a link to an issue if one exists.

## 1. Pin what you are verifying

```sh
git fetch origin '+refs/heads/*:refs/remotes/origin/*'   # explicit refspec, so origin/* is never stale
GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/nonexistent git worktree add --detach /tmp/verify-wildcard/tree-<short sha> <full head SHA you were asked to verify>   # that exact commit, never the branch tip; replace refs and grafts can't swap it
cd /tmp/verify-wildcard/tree-<short sha>
git status --porcelain                      # must print nothing: verify committed code only
swift package resolve --package-path ios/Packages/<Package>   # and pnpm --dir web install --frozen-lockfile once web/ exists
git rev-parse HEAD                          # the commit the verdict names
f=$(mktemp) && git show origin/main:scripts/verify-diff-hash.sh > "$f" && bash "$f" "$(git rev-parse HEAD)"; rm -f "$f"   # the diff the verdict covers, hashed by main's copy of the script; main itself gives e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 (empty)
git merge-base --is-ancestor origin/main HEAD || echo "behind main"
```

If the branch is behind main, say so in Notes: the author merges main in, and a new verdict follows if the diff changed.

Read the PR description (if there is no PR, the request that asked for the verdict) and the diff to decide which journeys in `features/` it touches. Always run every journey marked **Ready**.

Keep evidence in one folder outside the repo, so it survives cleanup. Shell variables don't survive between an agent's separate commands, so write the literal path, with the real short sha, in every command (below: `/tmp/verify-wildcard/<short sha>`):

```sh
mkdir -p /tmp/verify-wildcard/$(git rev-parse --short HEAD)
```

## 2. Launch the stack

In a cloud session the session-start hook starts Docker and local Supabase and prints `Ready: … Docker local Supabase.` A running stack serves whichever checkout started it, so from your worktree restart it to serve the code under test, and note that in the verdict:

```sh
docker info >/dev/null 2>&1 || (nohup dockerd >/tmp/dockerd.log 2>&1 &)   # Docker isn't running by default in cloud sessions
npx --yes supabase@2.121.0 stop
npx --yes supabase@2.121.0 start -x studio,imgproxy,mailpit,logflare,vector,supavisor,edge-runtime,postgres-meta
```

## 3. Health check

All must pass before you drive anything (the expected values come from a real run):

```sh
npx --yes supabase@2.121.0 status -o json   # prints API_URL http://127.0.0.1:54321 and an ANON_KEY
scripts/verify.sh supabase                  # resets the database from supabase/migrations; ends "Result: PASS" and "verify: ok"
```

If a service won't start, stop: the verdict is FAIL, reason "stack did not start", with `docker ps -a` and `docker logs supabase_db_wildcard` saved to `/tmp/verify-wildcard/<short sha>/`.

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
| **Database rows** | `docker exec supabase_db_wildcard psql -U postgres -c "select id, member_id, day, kind, payload from public.check_ins"` (and `check_in_squads`, `storage.objects`); the rows exist, and nothing immutable was edited or deleted |
| **What each member gets back** | Sign up real users (`/auth/v1/signup` with the anon key), act as each through `/rest/v1` and `/storage/v1`: squad-mates, someone in another squad, and a signed-out caller each get only what the rules allow |
| **What a user or agent sees** | <no internal error messages or internals in public-facing copy> |

Then try at least one thing the author may not have: the change's edge case, a wrong input, or a repeat of the same call. wildcard must refuse what it says it refuses.

## 6. Clean up

Stop only what you started: servers and watchers; the stack (`<stop command>`, which keeps data volumes) and a Docker daemon, if you started them; and the worktree (`git worktree remove /tmp/verify-wildcard/tree-<short sha>`). A stack you found running stays running; never wipe a stack or database you didn't create. The evidence folder stays.

## 7. The verdict

Return the report to the owner thread that asked for it, which posts it unedited in the PR's one verdict comment (`raise-pr`, Independent verification, step 5); without a PR, post it where the verdict was asked for. Save a copy as `/tmp/verify-wildcard/<short sha>/verdict.md`. Exactly one of:

- **PASS**: every journey you ran did what it should, and the evidence matches.
- **PASS+NOTES**: it works, with issues that don't block (each one named).
- **FAIL**: something didn't work, or couldn't be checked. Name the first failing step and its output.

```markdown
## Verifier verdict: PASS | PASS+NOTES | FAIL

Commit: <full head SHA>
Diff: <output of scripts/verify-diff-hash.sh, main's copy>

What I ran: each journey and command, and the key line it printed or what I saw (screenshots attached for anything users see). Journeys not run, and why.
Notes or failures: what's wrong or worth knowing, with the evidence, including the extra check you tried.
```

Quote real output lines, never paraphrase them. A verdict without a commit, a diff hash or evidence doesn't count.

## Keeping this skill current

The PR that adds something a user can do adds or fills in its file in `features/` and sets its row above to **Ready**. Changes to this skill are agent rules; see `raise-pr` (Merging) for when Tracy merges them.
