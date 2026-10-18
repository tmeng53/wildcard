# Wildcard — guide for agents

<!-- Follows the agent-instructions skill. Keep it under 200 lines. Working name; replace when the name is decided. -->

Wildcard is an iOS app where friend squads check in every day (练了 / 吃得干净 / 今日免责声明), see each other on a shared track, get a Sunday 战报 recap and share a weekly 3:4 schedule poster. Chinese-first UI. The MVP plan lives in the project's docs; this file holds how the code is built.

The shared rules and skills here come from `sponge-ai-lab/engineering-skills`. Change them there first, then copy the change in. The TypeScript skills (`verification`'s ESLint config, `module-structure`, `errors`, `zod`) apply to `web/` and `supabase/` as written; the Swift equivalents are in **Language practices** below.

## Layout

- `ios/` — the app. `Wildcard.xcodeproj` is a thin app target; all logic lives in local Swift packages under `ios/Packages/`.
- `web/` — the invite landing page (Next.js) that opens the App Clip or App Store.
- `supabase/` — migrations, row-level security policies, edge functions (TypeScript).

## Commands

- All checks that run without a Mac (the cloud stop hook runs this): `scripts/verify.sh`. It runs `swift test` for every package in `ios/Packages/`, and the web and backend checks once `web/` and `supabase/` exist.
- iOS build, UI tests and screenshots (Mac only): `scripts/ios-test.sh`, added with the Xcode project.
- Lint: SwiftLint and swift-format, configured with the first Swift package.

Add each command here in the PR that makes it real.

## CI

**No GitHub-hosted runners**: they cost money this project doesn't spend. Linux checks run in the agent's own session before every push. iOS build, UI tests and screenshots run on the self-hosted runner labelled `macos-self-hosted` (Tracy's Mac), so a PR touching `ios/` waits until that Mac is awake. Every workflow uses `runs-on: [self-hosted, macos-self-hosted]`.

## Skills

Read the matching skill before the work it covers.

| Skill | Use it |
| --- | --- |
| `verification` | Before calling anything done, and when writing tests or a PR's evidence. |
| `agent-instructions` | Before editing this file, `CLAUDE.md` or project instructions. |
| `module-structure` | Before adding a package or module (TypeScript as written; Swift per below). |
| `errors` | Before adding error handling in `web/` or `supabase/`. |
| `zod` | Before adding a schema or parsing untrusted input in TypeScript. |
| `address-review` | When a PR you own gets review comments. |
| `raise-pr` | Whenever you open or edit a pull request. |
| `verify-product` | When verifying another agent's change. The project's `verify-wildcard` skill is what a verifier follows. |
| `project-setup` | When PRs, decisions or friction keep stalling. |
| `cloud-test-environment` | When adding a service the tests need. |

## Architecture

Planned (update as packages land): packages by capability, each `Domain` (pure Swift, no SwiftUI/UIKit, builds on Linux) plus `UI` (SwiftUI) where needed: `CheckIn`, `Squad`, `Recap`, `Poster`, `Avatar`, `Onboarding`. Supporting packages: `DesignSystem` (colors, type, motion), `Backend` (Supabase client adapter). The app target only wires packages together.

## Domain rules

- Never use "奥运", the rings or "Olympic" in code-visible copy, assets or bundle names.
- All user-facing strings go through the String Catalog, Chinese (`zh-Hans`) first, English second.
- No body metrics, calories or macros anywhere in v1.

## Language practices

SwiftLint and swift-format enforce style; they are not repeated here.

- Swift 6 language mode with strict concurrency. No `@unchecked Sendable` without a comment saying why it is safe.
- **Module boundaries are packages.** A package imports another only through its public API; `Domain` targets never import SwiftUI, UIKit or `Backend`. Cross-capability types live in a small `Contracts` package.
- **Reuse before you add.** Search first. Shared code goes in a package named after its topic, never `Utils`, `Shared`, `Common` or `Helpers`.
- Parse at boundaries with `Codable` into strict types; stored and wire JSON carries a top-level `version`.
- Errors: one `enum` per package conforming to `Error` with a specific case per failure the caller can act on; use typed `throws(PackageError)`. `fatalError` only for broken invariants.
- Domain code never reads the clock, generates ids or does I/O directly: inject `Clock`, id generators and ports.
- No force unwraps (`!`) or `try!` outside tests.
- **Motion and feel are features.** Animations run at 60fps or better on device; no work on the main actor that can drop a frame. Use haptics deliberately, not on every tap.
- **Encode lessons in structure.** Prefer a type that makes a bad state unrepresentable, then a lint rule, then a runtime check.
- Public-facing copy never mentions internals.

## Testing and verification

- **Prove it works.** Run the feature the way users do before calling it done. UI changes attach simulator screenshots or a recording to the PR.
- Domain tests use Swift Testing (`@Test`, `#expect`) with literal expected values. Backend tests run against local Supabase in Docker, never a mocked database.
- Run `scripts/verify.sh` before every push.

## Pull requests

1. **Merge only by the project's merge rule.** Agents open PRs ready for review, written with the `raise-pr` skill; nothing merges without green checks, a clean review and an independent verifier's pass. **Merge rule:** the owner thread merges a PR itself only when it changes nothing a user can see (logic, backend, tooling, tests). Any PR that changes what users see or feel (screens, copy, motion, assets) waits for Tracy's OK on its screenshots, and a human merges changes to `AGENTS.md` and `.claude/skills/`.
2. **Never rewrite history others may rely on:** no force-pushes to `main`, no editing or deleting other people's comments.
3. **If agents can't agree** after one round of replies, post a reply starting with **Decision needed:** and stop work on that point until a human answers.
4. **Ground decisions in evidence:** link official docs (Apple, Supabase) or respected writing, or say there are none.
5. **When a decision or review comment would hold in any project,** open a PR adding it to `sponge-ai-lab/engineering-skills`.
6. **Surface design friction; don't absorb it.** Record it as a `friction` issue, work around it minimally, and tell the friction owner.

## Code Review Rules

Flag only real problems: bugs, broken rules, missing evidence. Formatting and anything SwiftLint, swift-format, ESLint or the compiler already catches are not findings.

- A `Domain` target importing SwiftUI, UIKit or `Backend`, or a package reaching into another's internals.
- A new helper that duplicates existing code, or lands in a `Utils`/`Shared`/`Common` package.
- Domain code that does I/O, reads the clock, or generates ids itself.
- Stored or wire JSON without a top-level `version`.
- A force unwrap or `try!` in shipped code, or `@unchecked Sendable` without a reason.
- A hard-coded user-facing string outside the String Catalog.
- A UI change without screenshots, a test that can't fail, or a mocked database.
- A PR that mixes unrelated changes.

## Keeping this file current

This file is code: change it in a PR, and only with rules that are true of the code or decided by the owner. Keep it under 200 lines; move a rule that needs more than a few lines into a skill and link it. When code and this file disagree, fix whichever is wrong in the same PR.
