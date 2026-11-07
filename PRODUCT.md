# Product

<!-- impeccable:product-schema 1 -->

The product record the Impeccable design skill (`.claude/skills/impeccable`) reads before any design work. It restates, for design, what `AGENTS.md` and the project's own instructions already decide; where they differ, `AGENTS.md` wins and this file is fixed in the same PR. The visual system is in `DESIGN.md`.

## Platform

ios

The app (`ios/`, SwiftUI, iOS 26) is the product. The website (`web/`, wildcardsquad.com: the home page, the `/join/<code>` invite page, privacy and terms) is a small static companion; treat it as `web` when a command targets it.

## Users

Chinese-speaking young professionals, 24 to 35, in North American metros, who train with a few friends. They check in on their phones, often right after a workout or a meal, and open the app again to see what their squad did.

## Product Purpose

Wildcard (外卡) is a check-in app for friend squads "training for the Games": each day a member posts 训练, 健康餐, 坦白放纵餐 or 今日请假条; the squad sees it on a shared scene, reacts and comments, gets a Sunday 战报 recap and shares a weekly 3:4 schedule poster (出赛表). Success is squads that keep checking in together because it is fun, never because they feel anxious. Slogan: 人人都是运动员.

## Positioning

A squad's own cast of drawn characters living on a scene they pick together, with a playful sports-broadcast voice (战报, 出赛表, 外卡), instead of a fitness tracker's numbers and streak guilt.

## Operating Context

- Chinese-first UI: Simplified Chinese by default, English second, Traditional Chinese on the website. Copy is short and specific; no help text telling people what to do or feel, no AI filler (稳, 赋能, 一站式).
- The Approved designs collection, linked from the project instructions, holds the latest design Tracy (the owner) approved for every screen and flow and is the source of truth for UI, copy and motion. Impeccable's commands refine work toward it; they never replace it. A new screen, a redesign or anything users see or feel is Tracy's call before it is built: show it, don't ship it.
- Design work is code-first. Never generate images with `impeccable generate-image` or comp rounds that bill an API key (the cloud machines carry the project's own keys); mockups follow the project's `/design` skill and start from real app screenshots.
- Subagents run only where `AGENTS.md` and the project's instructions allow (Sonnet for reviews and light verification); Impeccable's own authorization to spawn its agents does not override that.
- The browser tools (`live`, `generate`, `detect`, the Chrome extension) read HTML and CSS: use them only on `web/`, never on the app.
- Cloud sessions have no Mac, so `xcrun simctl` isn't there: the app's screenshots come from CI (`scripts/ios-test.sh`, the `ios-screenshots-<sha>` artifact) or a Mac running `scripts/ios-test.sh`.

## Capabilities and Constraints

- Native iOS first: where iOS has the component or behaviour (NavigationStack and its swipe back, sheets, pickers, tab bar, scrolling), use the system's; build our own only where an approved design asks for what the system can't do.
- What we tune lives in the database and ships as data (copy the API sends, catalogs, art, switches), not as app code.
- No body metrics, calories, weight or macros anywhere.
- Never "奥运", the rings or "Olympic" in names, copy, logo or assets.

## Brand Commitments

- Name Wildcard / 外卡, slogan 人人都是运动员; avoid 崽, 分身, 奥运, and 健康 as a brand word.
- Clean, cute, minimal and modern, with smooth motion. Template looks (grey page, white cards, full-width buttons), a "mini-program" feel, cream backgrounds, hot pink, glow, gradients, neon and spins are defects.
- The brand colour is graphite with white (`bgBrand`, `fgOnBrand`); each squad's scene brings its own colours.

## Evidence on Hand

- The app's own art: characters, coaches and scenes in `ios/Packages/Avatar` and `ios/Packages/CheckIn/SceneArt`; the website reuses it (`web/character`).
- CI screenshots of every screen (the `ios-screenshots-<sha>` artifact) and the style guide behind the `-styleguide` launch argument.
- No testimonials, press or usage numbers yet; don't invent any.

## Product Principles

1. Fun with friends, never guilt: no streak shaming, no anxiety.
2. The squad is the hero: their characters, their scene, their words.
3. One component per kind of thing, from the design system.
4. Native first, then our own only where it earns its place.
5. Say it in the fewest words a person would use.

## Accessibility & Inclusion

Labels, field names and buttons stay on one line at real copy lengths on the smallest supported phone (a UI test checks it). Every animation has a Reduce Motion path. Haptics are one per meaningful moment.
