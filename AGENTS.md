# Wildcard — guide for agents

<!-- Follows the agent-instructions skill. Keep it under 200 lines. Working name; replace when the name is decided. -->

Wildcard is an iOS app where friend squads check in every day (练了 / 健康餐 / 坦白放纵餐 / 今日请假条), see each other on a shared track, get a Sunday 战报 recap and share a weekly 3:4 schedule poster. Chinese-first UI. The MVP plan lives in the project's docs; this file holds how the code is built.

The shared rules and skills here come from `sponge-ai-lab/engineering-skills`. Change them there first, then copy the change in. The TypeScript skills (`verification`'s ESLint config, `module-structure`, `errors`, `zod`) apply to `web/`, `api/` and `supabase/` as written; the Swift equivalents are in **Language practices** below.

## Layout

- `ios/` — the app. `Wildcard.xcodeproj` is a thin app target; all logic lives in local Swift packages under `ios/Packages/`.
- `api/` — the HTTP API (TypeScript: Node, Hono, Zod, Kysely), the only way into the data. Supabase is its Postgres, Auth and Storage.
- `web/` — the invite landing page (Next.js) that opens the App Clip or App Store.
- `supabase/` — migrations, row-level security policies, edge functions (TypeScript).

## Commands

- All checks that run without a Mac (the cloud stop hook runs this): `scripts/verify.sh`. It runs `swift test` for every package in `ios/Packages/`, and the web, database and API checks once `web/`, `supabase/` and `api/` exist.
- Database: `scripts/verify.sh supabase` resets local Supabase from `supabase/migrations` and runs the pgTAP tests in `supabase/tests/database` (needs Docker and `supabase start`). CI runs it in a Linux job, since macOS runners have no Docker.
- API: `scripts/verify.sh api` installs `api/` with pnpm and runs ESLint, Prettier, `tsc`, dependency-cruiser (`pnpm --dir api boundaries`) and the Vitest tests, which use local Supabase's database and Auth (needs `supabase start`). After changing a route, `pnpm --dir api openapi` rewrites `api/apps/server/openapi.json`; a test fails while it is stale. Then `scripts/swift-openapi.sh` regenerates the app's Swift from it, the wire types (`ios/Packages/Contracts/Sources/APIContract/Generated`) and the client (`ios/Packages/Backend/Sources/Backend/Generated`), never edited by hand; `scripts/verify.sh` fails while they are stale. After a migration, `pnpm --dir api db-types` rewrites the Kysely table types (`src/adapters/tables.ts`) from local Supabase; `scripts/verify.sh` fails while they are stale.
- API journeys: `scripts/api-journeys.sh [check-in] [photo-upload] [squad] [disclaimer-drafts] [weekly-plan] [squad-today] [week-summary] [reactions] [replies] [devices] [daily-push] [weekly-awards] [account] [admin-mcp]` starts the built server against local Supabase and drives the `verify-wildcard` journeys over HTTP as the app would (needs `supabase start`); CI's `supabase` job runs it.
- App adapters, end to end: `scripts/verify.sh backend` starts the built API against local Supabase and runs `swift test` for `ios/Packages/Backend`, so the app's own sign-in and API client sign members in, save profiles, upload photos and post and read check-ins against the real API, database and Storage (needs `supabase start`); the `swift` part only builds it. CI runs it in the Linux job, whose image ships Swift.
- iOS build, UI tests and screenshots (macOS with Xcode 26 or newer): `scripts/ios-test.sh`. It boots the simulator first, runs a failed UI test once more and lists any that passed only then at the end of the log, and writes the screenshots the UI tests keep to `build/ios/screenshots/`; CI's `ios` job runs it and uploads them as the `ios-screenshots-<sha>` artifact.
- Avatar previews (macOS with Xcode 26 or newer): `scripts/avatar-preview.sh` renders the character through `AvatarUI` on an iOS simulator into `build/avatar/previews/` (outfit stills, cheer frames, GIFs, frame timings); CI's `avatar-preview` job uploads them as `avatar-previews-<sha>`, and with `PRINT_PREVIEWS=1` prints them base64 in the log for agents that can't download artifacts.
- Lint (part of `scripts/verify.sh`): `swift format lint --strict --recursive ios` (`.swift-format`) and `swiftlint lint --strict` (`.swiftlint.yml`). `swift format -i -r ios` fixes formatting. `scripts/install-swiftlint.sh` installs the pinned SwiftLint (`scripts/swiftlint-version`); with another version `scripts/verify.sh` ends inconclusive.

Add each command here in the PR that makes it real.

In Claude cloud sessions a SessionStart hook (`scripts/cloud-session-start.sh`) starts what the checks need, and a Stop hook (`scripts/verify-on-stop.sh`) runs `scripts/verify.sh` whenever the branch has changes of its own and blocks the first stop while it's red: fix it, or tell the user exactly what is red. If a toolchain or service isn't available, say that check is inconclusive; never skip or fake it.

Install any tool that helps the task (`apt`, `pip`, `npm`, a binary); cloud machines are yours and thrown away after the session. If every session should have it, add it to `scripts/cloud-session-start.sh` in a PR.

## CI

The repo is public until launch, so GitHub-hosted runners are free, macOS included. `.github/workflows/verify.yml` runs `scripts/verify.sh` (job `verify`), `scripts/ios-test.sh` (job `ios`) and `scripts/avatar-preview.sh` (job `avatar-preview`) on `macos-26`, and the database and API checks (job `supabase`) on Linux, for ready (not draft) PRs and pushes to `main` (on a PR, `ios` and `avatar-preview` run only when it changes what they build, else they're skipped, which counts as passing), and cancels a PR's run when a newer push to it replaces it (each commit on `main` keeps its own run); "green" means that check passed on the PR's head. Run `scripts/verify.sh` in your session before every push too; where a toolchain is missing there, CI's result is the evidence. Keep CI fast: a job should run only for the paths it checks (today only `ios` and `avatar-preview` are gated), a new check that can run on Linux goes in a Linux job, and fixes are checked locally and batched into one push, since every push queues for the few macOS runners. Never add a self-hosted runner while the repo is public: a fork's PR could run code on that machine. Never commit secrets, keys or private data; anything pushed while public stays public. Before launch the repo goes private, and the macOS builds move to Xcode Cloud.

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

Landed: `DesignSystem`, following the design system v4 canvas: a `DesignSystem` target (palette, color roles per scene, `CheckInKind`, type ramp, spacing, radii, control sizes, motion springs, haptics; pure Swift) and `DesignSystemUI` (SwiftUI bridges, the bundled Barlow Condensed font, the shared components, and the style guide behind the `-styleguide` launch argument). How it is tiered, what each component is for and when a piece belongs in it: `ios/Packages/DesignSystem/README.md`. Screens take colors, type, spacing, radii, control sizes, motion and haptics from `ColorRole`, `TypeRamp`, `Space`, `Radius`, `Sizing`, `Motion` and `Haptic`, never raw values, `Palette` or `sensoryFeedback` (SwiftLint checks); a size that belongs to one view only (a frame, a stroke) can stay in that view. A view only one screen needs can stay with that screen, built from those tokens; a generic or shared one goes in `DesignSystem`, drawn on the canvas first.

API (`api/`, a pnpm workspace): `apps/server` is the only app (routes, sign-in, wiring in `main.ts`), `packages/errors` holds `AppError` and RFC 9457 problem bodies, `packages/check-ins` is the first module (saving and listing check-ins, with every rule the database no longer enforces, a member's lifetime counts by kind for 我 (`/me/check-in-totals`), and the weekly plans 本周 counts against, `/me/weekly-plans/{weekStart}`, and a squad's week for the Sunday 战报, `/squads/{squadId}/weeks/{weekStart}/summary`; its stores are ports with Postgres adapters), `packages/members` holds a member's profile (`GET /me`, `PUT /me/profile`: time zone, 口头禅 and the character, a nickname and a look by the art's ids, which the API checks only in shape so new art is data-only; squadmates see the 口头禅 and character on the squad's today, the web invite page only the looks; the app saves it right after the first sign-in), and `packages/squads` holds squads (create with a name, join by invite code, leave; 1 to 8 members, at most 3 squads a member); check-ins ask it who is in which squad through their `SquadMembership` port, never its table. `packages/ai-consent` keeps each member's consent to having their words sent to AI providers (`/me/ai-consent`), by the version of the app's copy they agreed to; a new version (such as one naming another provider) asks again, and the consent goes only with the account. Creating or joining a squad, AI drafts and the weekly awards each need a current consent through their own port (the awards leave out anyone without one). `packages/typed-text` holds the rules for text people type. `packages/disclaimer-styles` is the one list of 请假条 styles (a contract: the meme library and the drafts both use it). `packages/memes` keeps the meme library the AI draws on for 今日请假条: memes Tracy approves from Claude's weekly picks, each used for 4 weeks unless turned off. `packages/disclaimer-drafts` writes AI 今日请假条 drafts (`POST /disclaimer-drafts`) from a member's reason and style, plus one meme in use that suits the style on 3 in 10 requests (never the whole library): the prompt, the checks every draft passes, and each member's 6 batches a day; the model sits behind its `LanguageModel` port, with an adapter per provider using structured output: OpenAI (GPT-5.4 mini, the default) and Anthropic (Claude Haiku 5.5). `LLM_PROVIDER` picks one, `LLM_MODEL` may name another of its models, and its key (`OPENAI_API_KEY` or `ANTHROPIC_API_KEY`) turns drafts on; without it the route answers 503 and the app shows its dice. Tests replay each provider's recorded responses, never live calls. `packages/weekly-awards` writes each squad's weekly awards (本周颁奖) once a week from the check-ins made before Sunday 8pm New York: 1 to 3 titles, each with a 颁奖词 and a move, for every member who checked in and agreed to AI use, through its own `LanguageModel` port (`AWARDS_LLM_PROVIDER`, GPT-6 Luna by default, `AWARDS_LLM_MODEL` may name another), stored with each member's most-reacted check-in (a row per winner, which a deleted account takes with it) and the failed tries; `apps/server/src/flows/weekly-awards.ts` tells the winners once by push and serves `GET /squads/{squadId}/weeks/{weekStart}/story`, `pending` (only the titles wait) until the model answers (what the awards may say is the prompt's job; the server checks only their shape), and `POST …/story/nudge` tells the admins once per failed try; a scheduler runs it every hour with `POST /jobs/weekly-awards`, and without an awards key every try fails as `AwardsModelMissingError`. `packages/push` keeps the phones each member gets push notifications on and sends through APNs with a `.p8` key (nothing is sent until `APNS_*` is set); a push carries String Catalog keys (`loc-key`), never words, so its copy is the app's. It also keeps each member's push switches (`/me/push-settings`, all on until turned off) and which days the daily push was handled. The daily progress push (`apps/server/src/flows/daily-progress-push.ts`) goes to each member once, at 6pm on their own clock: their squad's week and who did something for them, counted per kind since their last one from a list of interaction sources (teammates' reactions for now), so a new kind of interaction is a new source or kind, not new push code. A scheduler starts it with `POST /jobs/daily-progress-push` and `JOBS_TOKEN`; jobs are not part of `openapi.json`. Teammates' reactions on check-ins (one per member, like Strava's kudos, left in the app) and their replies to a 请假条 (准了 and the like, one per member, apart from reactions) live in `packages/check-ins`. Routes are declared with `@hono/zod-openapi`, so `openapi.json` comes from the code, and the app's wire types come from `openapi.json`: the Zod schemas are the one contract. Every JSON body carries a top-level `version`, every failure is `application/problem+json` with a stable `reason`, and signed-in routes check the Supabase access token against the project's published signing keys. Auth, Storage and Postgres are interfaces first, so a provider can be swapped: the server depends on the ports in `apps/server/src/ports.ts`, each provider is an adapter in `src/adapters/`, only adapters import a provider's library, and only `main.ts` picks one (dependency-cruiser enforces both). Auth, Postgres and photo Storage each have a port. Photos never pass through the API: `POST /photo-uploads` signs an upload URL in the caller's own folder, the app uploads straight to Storage, and a check-in refers to its photos by path. `DELETE /me` deletes an account (`apps/server/src/flows/delete-account.ts`, which spans modules): it re-checks the session with Auth, revokes Sign in with Apple once the .p8 key is configured, deletes the member's photo folder, then the Auth user, whose rows the database deletes by `on delete cascade`.

Landed: `Contracts`, with a `Contracts` target (ids, local days, the check-in as the app holds it; pure Swift, no dependencies) and `APIContract` (the API's wire types, generated from `openapi.json` by Apple's Swift OpenAPI Generator, and the mapping to and from `Contracts`; only adapters that talk to the API import it). A rule the app needs before it sends (a caption's length, how many photos) stays in `Contracts`, and a test checks it against `openapi.json`.

Admin MCP server: `/mcp` on the same API (Streamable HTTP, official `@modelcontextprotocol/server` SDK) gives admins tools to manage the app from an MCP client. Clients sign in with OAuth 2.1 through Supabase Auth's OAuth server, found from the 401's `WWW-Authenticate` and `/.well-known/oauth-protected-resource/mcp`; the server takes only a token issued to an OAuth client (never our app's own sign-in) from a member in the `admins` table (`packages/admins`, added by hand). Each tool (`apps/server/src/admin-mcp/tools/`) works through a module's public functions, never tables, and every tool that changes something is logged to `admin_actions` in the same transaction as the change (each tool gets the database or a transaction of it). The consent page (`apps/server/src/admin-mcp/consent-page.ts`, at `/oauth/consent`, so Supabase's site URL is the API's) is plain HTML the API serves: the admin signs in again on it for each request (Sign in with Apple; email and password only where `ADMIN_PASSWORD_SIGN_IN=on`, for local stacks), only an admin can approve, and that sign-in is signed out once they answer. None of it is part of `openapi.json`.

Landed: `Avatar`, the character player: `AvatarDomain` (SVG-subset art, rig, keyframe clips, `Performance` blending idle and one-shot clips; pure Swift, the caller passes the time), `AvatarArt` (the placeholder character's SVG parts and clip JSON) and `AvatarUI` (`CharacterView`, drawn with `Canvas` in a `TimelineView`). A look picks an SVG variant per slot (`body` for the species or skin tone, then hair, a face of eyes, brows, mouth, cheeks and glasses, hat, top, bottom, prop; a slot left out wears the rig's default) and may recolor body, hair, eyes, brows, top and bottom from preset swatches (a variant's `tones.json` says which of its colors follow); a `Persona` picks the idle and cheer clips, and any look plays any persona, with its species' own moves (a cat's yawn, a dog's wag) layered on top as accent clips.

Landed: `CheckIn`, the app's first screen: `CheckInDomain` (pure Swift: `TodayStore`, the observable data the home and 打卡 bind to: the squad's today, the week's plan and recent check-ins, with the member's own posts counted at once; posts get their id, day and time when made, wait in an outbox on the device and go out by id, so a retry saves once; reactions; and the home scene's rules in `Stage/`: who stands where on each scene, poses, day and night, who cheers) and `CheckInUI` (今天: the top card, the check-in burst, photo step, compose page, 请假条 page and the payoff on the scene). It reaches the server through its `CheckInBackend`, `Outbox` and `DisclaimerWriter` ports, whose adapters are in `Backend` (`APICheckInBackend`, which keeps a copy of the last home on the device; `DeviceOutbox`; `APIDisclaimerWriter`, dice when the AI can't write); until sign-in lands the app passes an in-memory squad and dice-only drafts.

Landed: `CharacterEditor`, the screen that dresses and names the character (sign-up step, and later 我): `CharacterEditorDomain` (the draft: picks and colors, undo, shuffle, the nickname rule; pure Swift) and `CharacterEditorUI` (the screen, and the catalog it reads from `AvatarArt`, whose `editor.json` groups bodies by species and lists this release's props).

Landed: `Account`, signing in: `AccountDomain` (`AccountSession`, which signs in with a credential, keeps the session in a `SessionStore`, hands out a current access token and renews it once however many callers ask; the provider is an `AuthProvider` port) and `AccountUI` (Sign in with Apple's button and nonce, the Keychain store). `Backend` holds the adapters: `SupabaseAuth`, the only app code that knows Supabase Auth's HTTP API, so changing provider means replacing it; and `WildcardAPI`, the client of our API, which the generator writes from `openapi.json` (`Generated/`, by `scripts/swift-openapi.sh`) behind calls in `Contracts` types, sending the session's access token and renewing it once when the API refuses it. A debug-only test-member credential signs in with a password on local Supabase, since the simulator and CI can't do a real Sign in with Apple.

Landed: `Notifications`, push on this phone: `NotificationsDomain` (`PushRegistration`: asks for permission only after the member's first check-in, never at sign-up, asks APNs for the token on every launch once allowed, and registers it through its `DeviceRegistry` port while someone is signed in; pure Swift) and `NotificationsUI` (the system prompt and APNs registration, taps on a notification, and which APNs servers this build's tokens are for). `Backend`'s `APIDeviceRegistry` is the registry, over `PUT /me/devices`.

Planned (update as packages land): packages by capability, each `Domain` (pure Swift, no SwiftUI/UIKit, builds on Linux) plus `UI` (SwiftUI) where needed: `Squad`, `Recap`, `Poster`, `Onboarding`. Supporting packages: `DesignSystem` (colors, type, motion), `Backend` (provider adapters and the API client). The app target only wires packages together.

## Domain rules

- Never use "奥运", the rings or "Olympic" in code-visible copy, assets or bundle names.
- All user-facing strings go through the String Catalog, Chinese (`zh-Hans`) first, English second. One exception: the Sunday 战报's award, count and reaction words come from the API (`apps/server/src/routes/week-summary-copy.ts`, in the language the app asks for), so a new award or count ships without an app release; the app shows any kind from the words it is sent.
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
- **Motion and feel are features.** Animations run at 60fps or better on device; no work on the main actor that can drop a frame. Haptics come from `Haptic`: one per meaningful moment, never on every tap.
- **Encode lessons in structure.** Prefer a type that makes a bad state unrepresentable, then a lint rule, then a runtime check.
- Public-facing copy never mentions internals.

## Testing and verification

- **Prove it works.** Run the feature the way users do before calling it done. UI changes attach simulator screenshots or a recording to the PR.
- Domain tests use Swift Testing (`@Test`, `#expect`) with literal expected values. Backend tests run against local Supabase in Docker, never a mocked database.
- **Someone else passes it, as deep as the change is risky.** The owner picks a tier from the diff and names it in the PR: CI only (docs, tests, a small fix with its test), light (a small UI change or one module's logic; the verifier reads the diff, CI and screenshots and tries an edge case) or full (contract, schema, auth, privacy, user data, AI, a new flow, across modules). A verifier is a fresh agent that did not write the change; it gets only the task and the diff, works from a clean checkout of the pushed commit, and returns PASS, PASS+NOTES or FAIL with evidence, naming the head commit and the diff hash from `scripts/verify-diff-hash.sh`. It starts when the PR is marked ready, alongside CI, quotes CI's result for the head instead of rerunning it, and spends its time on what CI can't show. One run per diff; after a fix it checks only the delta, unless the fix reaches past the findings or touches the contract or schema. CI, a code review and the author's own review are not a verdict. How, in `raise-pr` (Independent verification).
- Run `scripts/verify.sh` before every push.

## Pull requests

- Branch from `main`. One small change per PR. **Never stack** a PR on another open PR.
- Run `scripts/verify.sh` first. Open the PR as a draft and mark it ready once it passes: CI runs only on ready PRs.
- **No light- or full-tier PR merges without a verifier's PASS or PASS+NOTES for its current diff.** A FAIL goes back to the author, or to a human if the author disputes it; a change to the diff after the verdict needs a new verdict from a new verifier.
- Write it with the `raise-pr` skill. The **Verification** section lists each command you ran and what it printed, or "inconclusive" and why. Anything users see carries screenshots or a recording.
- **Get a code review once the PR is ready, and again only when a new head needs one.** A fresh Claude agent that did not write the PR reviews the green head under the Code Review Rules below; tier 1 PRs (docs only, tests only, a typo, or a small fix with its test) skip it and rely on CI. Bigger PRs (features, API, contract or schema, architecture, new dependencies, large refactors) also get one `@codex review` comment after CI and the verifier both pass, which never holds a merge more than 30 minutes; at most two per PR, since Codex usage is limited. How, in `raise-pr`.
- **Match the model to the work, since tokens are limited.** Simple, mechanical work runs on Sonnet: code reviews, light verification, docs, lists, status and diagram updates. Writing real code and design work stay on Opus. When you start a subagent for simple work, pass `model: "sonnet"`.
- **Review feedback is a symptom, not a to-do list.** Every finding (a person's, a bot's, a verifier's note) is a claim to check before acting; answer each on the PR, fixed (with the commit) or not and why. Read the whole review first and group findings by cause. When a PR gets findings a second time, post one short root-cause note before pushing a fix, then rework it into the simplest design. When in doubt, ask a human.
- **Who merges:** the owner thread merges most PRs itself once they're green, verified and reviewed. Tracy merges a key technical decision or a major UI change she didn't ask for. The exact rule is in `raise-pr` (Merging).
- Only change what the PR is about. Never force-push `main`; never edit or delete other people's comments.
- **A change removes what it replaces.** When a decision changes, the PR that builds the new way deletes the old one everywhere (app, API, database, docs, AGENTS.md), even in other packages. Removing it is in scope; a PR isn't done while the old path still exists.
- **No backward compatibility until real users.** Edit migrations, stored shapes and names in place; no shims, no add-then-alter migrations.
- **When a parallel PR lands, the later one wires them together** (or opens an issue saying what is left unwired).
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
- A hard-coded user-facing string outside the String Catalog (other than the 战报 words the API sends).
- A UI change without screenshots, a test that can't fail, or a mocked database.
- A PR based on another open PR, or one that mixes unrelated changes.
- A verification tier lower than the diff warrants (`raise-pr`, Independent verification).
- Code the change leaves dead or duplicated (an old rule kept after it moved, a second type for the same thing), or an old name after a rename.

## Keeping this file current

This file is code: change it in a PR, and only with rules that are true of the code or decided by the owner. Keep it under 200 lines; move a rule that needs more than a few lines into a skill and link it. When code and this file disagree, fix whichever is wrong in the same PR.
