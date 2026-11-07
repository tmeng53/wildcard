# Design System: Wildcard

This file points the Impeccable design skill (`.claude/skills/impeccable`) and every other design agent at Wildcard's design system; it holds no token values of its own, so nothing here can drift from the code. The values live in the design system v4 canvas (linked from the project instructions) and in `ios/Packages/DesignSystem`, whose tests pin every token to the canvas. Never write a YAML token block or `.impeccable/design.json` sidecar here: `/impeccable document` and `extract` don't apply, since the package and its README are the record.

## Overview

Clean, cute, minimal and modern. A squad's drawn characters on the scene they picked are the colour and the life of the app; the chrome around them stays quiet, graphite and white. The app is light only (`UIUserInterfaceStyle = Light`), on iOS 26 with Liquid Glass.

Read, in this order, before any UI work: `ios/Packages/DesignSystem/README.md` (tiers, every component and when to use it, haptics, how to add to it), the Approved designs collection for the screen at hand, then the code.

## Colors

- Screens ask for a role (`ColorRole`: `bg*`, `fg*`, `border*`), never a hex or `Palette`; SwiftLint rejects a raw colour outside the package.
- The brand (`bgBrand`, `fgOnBrand`) is graphite and white and never follows the scene. Brand screens set `.accentTone(.brand)` at their root; the squad's turf (home, the check-in burst, 出赛表, 战报) keeps the scene's tone from `SceneTheme`.
- Red (`fgDanger`) only colours the words of an action that can't be undone.
- Scene colours are not differences from a design: they come from the squad's theme.

## Typography

- `TypeRamp` only (SwiftLint rejects system text styles in screens). It scales with Dynamic Type through `relativeTo:`; a few drawn pieces (the poster, the launch word, the character's stage) pin their size on purpose.
- PingFang SC carries the UI; Barlow Condensed is for numbers and the wordmark only.
- Labels, field names and buttons never wrap at real copy lengths.

## Layout

`Space`, `Radius` and `Sizing` only. Tap targets at least 44 points. Content stays inside the safe area and clear of the tab bar, keyboard and floating bars.

## Elevation & Depth

Liquid Glass only on controls that float (bars, headers, menus, controls over the scene or photos); buttons and cards in a page's content stay solid. No glow, no coloured halos, no gradients, no neon.

## Shapes

Capsule buttons, rounded cards from `Radius`, round 44-point header buttons. No tilted or stamp-like decorations.

## Components

Use the package's component for its kind of thing, and extend it before making a variant (one component per kind of thing). Navigation is the system's: pages push on the tab's NavigationStack with `pushedPage()`, tabs are `AppTabs`. Popups are `glassMenu` / `glassConfirm` (approved 2026-11-04), not the system `Menu`, `contextMenu` or `confirmationDialog`. A new component or variant is drawn on the v4 canvas before it is coded.

## Do's and Don'ts

### Do:

- Start a mockup from a real app screenshot and the design system's components, changing only what is asked.
- Use the app's own art (characters, scenes, SF Symbols as the components use them) for icons and figures.
- Give motion one meaningful moment, a `Motion` spring and at most one `Haptic`, with a Reduce Motion path, at 60 fps or better.
- Check every screenshot on the smallest supported phone and with long text for clipping and overlap.

### Don't:

- Don't follow a generic command over this file: `bolder`, `colorize`, `delight` and `overdrive` never add glow, gradients, neon, spins, cream, hot pink or a new colour outside `ColorRole`; `typeset` never swaps the fonts.
- Don't read Impeccable's iOS guidance as licence to change what the design system decided: semantic colours mean `ColorRole`, text styles mean `TypeRamp`, and its "platform menus and action sheets" mean our `glassMenu`.
- Don't design or build a dark mode, and don't read Impeccable's dark-mode or `prefers-color-scheme` advice as a gap: the app is light mode only (`UIUserInterfaceStyle = Light`) and so is the website's design system.
- Don't count the squad's status rings, the score or the week's progress as "progress rings standing in for content": they are the content.
- Don't use emoji or Unicode glyphs as icons, a grey box around a single row or link, explanatory help text, or a template look (grey page, white cards, full-width buttons).
