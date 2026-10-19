# Wildcard — guide for agents

<!-- Follows the agent-instructions skill. Keep it under 200 lines. Working name; replace when the name is decided. -->

Wildcard is an iOS app where friend squads check in every day (练了 / 吃得干净 / 今日免责声明), see each other on a shared track, get a Sunday 战报 recap and share a weekly 3:4 schedule poster. Chinese-first UI. The MVP plan lives in the project's docs; this file holds how the code is built.

The shared rules and skills here come from `sponge-ai-lab/engineering-skills`. Change them there first, then copy the change in. The TypeScript skills (`verification`'s ESLint config, `module-structure`, `errors`, `zod`) apply to `web/`, `api/` and `supabase/` as written; the Swift equivalents are in **Language practices** below.

## Layout

- `ios/` — the app. `Wildcard.xcodeproj` is a thin app target; all logic lives in local Swift packages under `ios/Packages/`.
- `api/` — the HTTP API (TypeScript: Node, Hono, Zod, Kysely), the only way into the data. Supabase is its Postgres, Auth and Storage.
- `web/` — the invite landing page (Next.js) that opens the App Clip or App Store.
- `supabase/` — migrations, row-level security policies, edge functions (TypeScript).

## Commands

- All checks that run without a Mac (the cloud stop hook runs this): `scripts/verify.sh`. It runs `swift test` for every package in `ios/Packages/`, and the web, database and API checks once `web/`, `supabase/` and `api/` exist.
- Database: `scripts/verify.sh supabase` resets local Supabase from `supabase/migrations` and runs the pgTAP tests in `supabase/tests/database` (needs Docker and `supabase start`). CI runs it in a Linux job, since macOS runners have no Docker.
- API: `scripts/verify.sh api` installs `api/` with pnpm and runs ESLint, Prettier, `tsc`, dependency-cruiser (`pnpm --dir api boundaries`) and the Vitest tests, which use local Supabase's database and Auth (needs `supabase start`). After changing a route, `pnpm --dir api openapi` rewrites `api/apps/server/openapi.json`; a test fails while it is stale. Then `scripts/swift-openapi.sh` regenerates the app's Swift types from it (`ios/Packages/Contracts/Sources/APIContract/Generated`, never edited by hand); `scripts/verify.sh` fails while they are stale. After a migration, `pnpm --dir api db-types` rewrites the Kysely table types (`src/adapters/tables.ts`) from local Supabase; `scripts/verify.sh` fails while they are stale.
- iOS build, UI tests and screenshots (macOS with Xcode 26 or newer): `scripts/ios-test.sh`. It writes the screenshots the UI tests keep to `build/ios/screenshots/`; CI's `ios` job runs it and uploads them as the `ios-screenshots-<sha>` artifact.
- Avatar previews (macOS with Xcode 26 or newer): `scripts/avatar-preview.sh` renders the character through `AvatarUI` on an iOS simulator into `build/avatar/previews/` (outfit stills, cheer frames, GIFs, frame timings); CI's `avatar-preview` job uploads them as `avatar-previews-<sha>`, and with `PRINT_PREVIEWS=1` prints them base64 in the log for agents that can't download artifacts.
- Lint (part of `scripts/verify.sh`): `swift format lint --strict --recursive ios` (`.swift-format`) and `swiftlint lint --strict` (`.swiftlint.yml`). `swift format -i -r ios` fixes formatting. `scripts/install-swiftlint.sh` installs the pinned SwiftLint (`scripts/swiftlint-version`); with another version `scripts/verify.sh` ends inconclusive.

Add each command here in the PR that makes it real.

In Claude cloud sessions a SessionStart hook (`scripts/cloud-session-start.sh`) starts what the checks need, and a Stop hook (`scripts/verify-on-stop.sh`) runs `scripts/verify.sh` whenever the branch has changes of its own and blocks the first stop while it's red: fix it, or tell the user exactly what is red. If a toolchain or service isn't available, say that check is inconclusive; never skip or fake it.

Install any tool that helps the task (`apt`, `pip`, `npm`, a binary); cloud machines are yours and thrown away after the session. If every session should have it, add it to `scripts/cloud-session-start.sh` in a PR.

## CI

The repo is public until launch, so GitHub-hosted runners are free, macOS included. `.github/workflows/verify.yml` runs `scripts/verify.sh` (job `verify`), `scripts/ios-test.sh` (job `ios`) and `scripts/avatar-preview.sh` (job `avatar-preview`) on `macos-26`, and the database and API checks (job `supabase`) on Linux, for ready (not draft) PRs and pushes to `main`, and cancels a PR's run when a newer push to it replaces it (each commit on `main` keeps its own run); "green" means that check passed on the PR's head. Run `scripts/verify.sh` in your session before every push too; where a toolchain is missing there, CI's result is the evidence. Never add a self-hosted runner while the repo is public: a fork's PR could run code on that machine. Never commit secrets, keys or private data; anything pushed while public stays public. Before launch the repo goes private, and the macOS builds move to Xcode Cloud.

## Skills

Read the matching skill before the work it covers.

| Skill | Use it |
| --- | --- |
| `verification` | Before calling anything done, and when writing tests or a PR's evidence. |
| `agent-instructions` | Before editing this file, `CLAUDE.md` or project instructions. |
| `module-structure` | Before adding a package or module (TypeScript as written; Swift per below). |
| `errors` | Before adding error handling in `web/`, `api/` or `supabase/`. |
| `zod` | Before adding a schema or parsing untrusted input in TypeScript. |
| `address-review` | When a PR you own gets review comments. |
| `raise-pr` | Whenever you open, edit or merge a pull request. Covers the verifier's verdict and who merges. |
| `wildcard-docs` | At the start of every session, and when you open an issue, need something from another developer, or need a human decision. |
| `verify-wildcard` | When you verify a change you didn't write, or prove a user journey works end to end. |
| `project-setup` | When PRs, decisions or friction keep stalling. |
| `cloud-test-environment` | When adding a service the tests need. |

## Architecture

Landed: `DesignSystem`, with a `DesignSystem` target (palette and color roles, type ramp, spacing, motion springs; pure Swift) and `DesignSystemUI` (SwiftUI bridges, the bundled Barlow Condensed font, the style guide the app opens on until the first feature screen). Screens take colors, type, spacing, radii, control sizes and motion from `ColorRole`, `TypeRamp`, `Space`, `Radius`, `Sizing`, `Tint` and `Motion`, never raw values; a size that belongs to one view only (a frame, a stroke) can stay in that view.

API (`api/`, a pnpm workspace): `apps/server` is the only app (routes, sign-in, wiring in `main.ts`), `packages/errors` holds `AppError` and RFC 9457 problem bodies, and `packages/check-ins` is the first module (saving and listing check-ins, with every rule the database no longer enforces; its store is a port with a Postgres adapter). Routes are declared with `@hono/zod-openapi`, so `openapi.json` comes from the code, and the app's wire types come from `openapi.json`: the Zod schemas are the one contract. Every JSON body carries a top-level `version`, every failure is `application/problem+json` with a stable `reason`, and signed-in routes check the Supabase access token against the project's published signing keys. Auth, Storage and Postgres are interfaces first, so a provider can be swapped: the server depends on the ports in `apps/server/src/ports.ts`, each provider is an adapter in `src/adapters/`, only adapters import a provider's library, and only `main.ts` picks one (dependency-cruiser enforces both). Auth, Postgres and photo Storage each have a port. Photos never pass through the API: `POST /photo-uploads` signs an upload URL in the caller's own folder, the app uploads straight to Storage, and a check-in refers to its photos by path.

Landed: `Contracts`, with a `Contracts` target (ids, local days, the check-in as the app holds it; pure Swift, no dependencies) and `APIContract` (the API's wire types, generated from `openapi.json` by Apple's Swift OpenAPI Generator, and the mapping to and from `Contracts`; only adapters that talk to the API import it). A rule the app needs before it sends (a caption's length, how many photos) stays in `Contracts`, and a test checks it against `openapi.json`.

Landed: `Avatar`, the character player: `AvatarDomain` (SVG-subset art, rig, keyframe clips, `Performance` blending idle and one-shot clips; pure Swift, the caller passes the time), `AvatarArt` (the placeholder character's SVG parts and clip JSON) and `AvatarUI` (`CharacterView`, drawn with `Canvas` in a `TimelineView`). A look picks an SVG variant per slot (`body` for the species or skin tone, then hair, hat, top, bottom, prop) and may recolor body, hair, top and bottom from preset swatches (a variant's `tones.json` says which of its colors follow); a `Persona` picks the idle and cheer clips, and any look plays any persona.

Planned (update as packages land): packages by capability, each `Domain` (pure Swift, no SwiftUI/UIKit, builds on Linux) plus `UI` (SwiftUI) where needed: `CheckIn`, `Squad`, `Recap`, `Poster`, `Onboarding`. Supporting packages: `DesignSystem` (colors, type, motion), `Backend` (Supabase client adapter). The app target only wires packages together.

## Domain rules

- Never use "奥运", the rings or "Olympic" in code-visible copy, assets or bundle names.
- All user-facing strings go through the String Catalog, Chinese (`zh-Hans`) first, English second.
- No body metrics, calories or macros anywhere in v1.

## Language practices

SwiftLint and swift-format enforce style; they are not repeated here.

- Swift 6 language mode with strict concurrency (needs Xcode 26 or newer; the app targets iOS 26). No `@unchecked Sendable` without a comment saying why it is safe.
- **Module boundaries are packages.** A package imports another only through its public API; `Domain` targets never import SwiftUI, UIKit, `Backend` or `APIContract`. Cross-capability types live in a small `Contracts` package.
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
- **Someone else passes it.** Every PR needs a verdict from a fresh agent that did not write it. It gets only the task and the diff, runs the change from a clean checkout of the pushed commit, and returns PASS, PASS+NOTES or FAIL with evidence, naming the head commit and the diff hash from `scripts/verify-diff-hash.sh`. One run per diff, once the PR is ready; a change to the diff needs a new verdict. CI, a code review and the author's own review are not a verdict. How, in `raise-pr` (Independent verification).
- Run `scripts/verify.sh` before every push.

## Pull requests

- Branch from `main`. One small change per PR. **Never stack** a PR on another open PR.
- Run `scripts/verify.sh` first. Open the PR as a draft and mark it ready once it passes: CI runs only on ready PRs.
- **No PR merges without a verifier's PASS or PASS+NOTES for its current diff.** A FAIL goes back to the author, or to a human if the author disputes it; a change to the diff after the verdict needs a new verdict from a new verifier.
- Write it with the `raise-pr` skill. The **Verification** section lists each command you ran and what it printed, or "inconclusive" and why. Anything users see carries screenshots or a recording.
- **Get a code review once the PR is ready, and again only when a new head needs one.** If Codex is installed on the repo, post one `@codex review` comment once the head is green; otherwise, or when Codex can't review, a fresh Claude agent that did not write the PR reviews that head under the Code Review Rules below. How, in `raise-pr`.
- **Review feedback is a symptom, not a to-do list.** Every finding (a person's, a bot's, a verifier's note) is a claim to check before acting; answer each on the PR, fixed (with the commit) or not and why. Read the whole review first and group findings by cause. When a PR gets findings a second time, post one short root-cause note before pushing a fix, then rework it into the simplest design. When in doubt, ask a human.
- **Who merges:** the owner thread merges most PRs itself once they're green, verified and reviewed. Tracy merges a key technical decision or a major UI change she didn't ask for. The exact rule is in `raise-pr` (Merging).
- Only change what the PR is about. Never force-push `main`; never edit or delete other people's comments.
- **If agents can't agree** after one round of replies, post a **Decision needed:** where the discussion is (`wildcard-docs`) and stop work on that point until a human answers.
- **Ground decisions in evidence:** link one to three credible sources (Apple, Supabase, standards, well-known engineering blogs), or say there are none.
- **When a decision or review comment would hold in any project,** also open a PR adding it to `sponge-ai-lab/engineering-skills`.

## Friction

- **Report friction the moment you hit it.** When the architecture, a boundary or an abstraction makes the work harder (a workaround, a rule written twice, a port that can't say what you need, a change that ripples through many packages), open a GitHub issue labelled `friction`: what you were doing, what got in the way, the workaround, and the fix you'd suggest. Keep going with the smallest clean workaround; don't start the refactor yourself. Then tell the friction owner the project instructions name.
- **The friction owner reviews each report against the whole list.** On a recurring theme or a severe report with a clear fix, it acts at once; otherwise it asks a human to decide.

## Code Review Rules

Flag only real problems: bugs, broken rules, missing evidence. Formatting and anything SwiftLint, swift-format, ESLint or the compiler already catches are not findings.

- A `Domain` target importing SwiftUI, UIKit, `Backend` or `APIContract`, or a package reaching into another's internals.
- A hand edit to generated code (`APIContract/Generated`), or a wire type written by hand instead of generated.
- A new helper that duplicates existing code, or lands in a `Utils`/`Shared`/`Common` package.
- Domain code that does I/O, reads the clock, or generates ids itself.
- Stored or wire JSON without a top-level `version`.
- A force unwrap or `try!` in shipped code, or `@unchecked Sendable` without a reason.
- A hard-coded user-facing string outside the String Catalog.
- A UI change without screenshots, a test that can't fail, or a mocked database.
- A PR based on another open PR, or one that mixes unrelated changes.

## Keeping this file current

This file is code: change it in a PR, and only with rules that are true of the code or decided by the owner. Keep it under 200 lines; move a rule that needs more than a few lines into a skill and link it. When code and this file disagree, fix whichever is wrong in the same PR.
