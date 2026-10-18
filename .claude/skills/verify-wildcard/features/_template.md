<!-- Template from engineering-skills/verify-product. Copy once per user journey, name the file after the journey, and delete this comment. -->

# <Journey name>

**Status: <Ready | On main, not drivable | Not on main yet>.** <Ready: since which change, and whether CI runs it. On main, not drivable: what is missing to drive it. Not on main yet: the PR expected to land it; that PR fills in this file and sets its row in `SKILL.md` to Ready.>

<What the user does, in two or three sentences, and what is still a stand-in.>

Code: `<where the journey's steps live>`.

## Drive it

```sh
<command> 2>&1 | tee /tmp/verify-<product>/<short sha>/<journey>.log
```

<What it sets up on its own, starting from an empty stack.>

## Expected output

Ids, times and hashes differ each run; the shape doesn't:

Copied from a real run:

```text
<the lines it prints, with changing values shown as <...>>
```

Any thrown error, a missing line or a different value is a FAIL.

## Evidence

Check at the source, with the ids from the log (queries in `SKILL.md`, step 5):

- <external system state: what it must say>
- <database rows: which rows, or "none for this journey yet">
- <what the user sees>

## Worth probing

<The edge cases most likely to break if the change touches this journey: each must be refused with an error that names the reason, and nothing may change.>
