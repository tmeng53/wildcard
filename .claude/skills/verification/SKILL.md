---
name: verification
description: How to prove a change works and how to write tests that can fail. Use before calling any task done, when writing or reviewing tests, and when filling a PR's Verification section.
---

# Verification

Every claim that something works comes with evidence from the real thing, not a proxy. Adapted from [pstack](https://github.com/cursor/plugins/tree/main/pstack) (MIT).

## Prove it works

- Before you call a task done, run it: call the feature the way its callers do and read the real output. "It compiles" and "tests pass" are not proof of a feature.
- Every PR's **Verification** section lists each command you ran and the key line it printed. If a check couldn't run, write "inconclusive" and why.
- Each commit and PR ends in a state you can check, ordered so the sequence proves itself (for example a failing test, then the fix).

- **Match the approved design.** Where the project keeps approved designs, put the approved design and the actual screen side by side for every UI change. A difference the owner didn't agree to is a failure, not a note; anything that can't match is raised with the owner before merge, never left as a silent placeholder. Differences that come from a theme the design says varies (such as scene colours) are not differences.
- **Look at every screenshot yourself.** Before sending screenshots or calling a UI change verified, check each one (smallest supported phone, long text where the screen has any) for content that is clipped, cut off, covered by buttons, keyboard or tab bar, or overlapping. Any such flaw is a failure, not a note. Where layout is at risk, add a UI test asserting the content's frames stay inside the visible area and clear of the controls over it.

## Tests that can fail

- **Test behavior, not implementation.** Call the code the way its users do and assert a literal expected value or observable effect.
- Before keeping a test, ask: would it still pass if every function it imports returned `undefined`? If yes, rewrite or delete it.
- Don't use matchers that pass for almost anything (`toBeDefined`, `toBeTruthy`, `toBeInstanceOf`, `not.toThrow`, bare `toHaveBeenCalled`).
- **Don't mock what you can run.** Storage tests use the real database in a throwaway container, never an in-memory stand-in. Mock only systems you can't run locally, and say why on that line.
- No focused or skipped tests in a commit.

## Types that make bugs unrepresentable

- No `as` casts: parse with a schema, narrow, or use `satisfies`. `as const` is fine.
- A `switch` over a union has no `default` that would hide a new member.
- More than two parameters become one object.
- Shipped code logs through a structured logger, never the console.

## Enforced

`templates/eslint.config.js` turns every rule above that a linter can check into an error: the banned matchers, no mocks, no focused or skipped tests, no casts, exhaustive switches, max two parameters, no console. It also carries the `errors` skill's rule. Copy it to the repo root.
