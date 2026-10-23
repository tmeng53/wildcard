# DesignSystem

The app's look and feel in one package: tokens, components and haptics. Screens build from it by name, so the app reads as one thing and a design change lands in one place. The source of truth is the design system v4 canvas, owned by the design thread; this package follows it, and the style guide (`-styleguide` launch argument, screenshotted by CI) shows what the package draws.

## Tokens: three tiers

Like Material 3's reference, system and component tokens, and Atlassian's `color.background.*` names:

| Tier | Where | Who uses it |
| --- | --- | --- |
| Primitive | `Palette` (every hex, by name) | Only this package and the character's art |
| Semantic | `ColorRole` (`bg*`, `fg*`, `border*`, per scene through `SceneTheme`), `TypeRamp`, `Space`, `Radius`, `Sizing`, `Motion`, `Haptic` | Screens and components |
| Component | Each component's own choice of semantic tokens, and sizes that belong to one view | That component |

A screen never names a primitive: it asks for a role (`fgMuted`, `bgAccent`), and the scene decides the color. Check-in kinds have no colors of their own; they use the scene's.

Brand vs scene: the brand's colour (`bgBrand`, `fgOnBrand`, from `Palette.brand` and `Palette.onBrand`) is its own value and never follows the scene, so it can change in one place. Brand screens (opening, sign-up, 我, the tab bar, writing a post, 请假条, the feed) set `.accentTone(.brand)` once at their root, and the primary button, selection marks, switches and text cursor inside wear the brand. The squad's own turf (home, the check-in burst, the 出赛表 poster, 战报) keeps the default `.scene`; the feed's kind tag still uses the scene's wash (`bgAccentSubtle`, `fgAccent`).

## Components

| Component | Use it for |
| --- | --- |
| `PrimaryButtonStyle`, `SecondaryButtonStyle`, `TextButtonStyle` | The one primary action (52, the accent tone: scene or brand), a second action (44, grey), a quiet text action |
| `AppleButtonStyle` | Confirming with Apple (注销), in Apple's own black as its button guidelines ask |
| `HeaderButton`, `StepHeader`, `StepSegments` | A 44-point round header button; a sign-up step's back button and ink segments |
| `CategoryBar` | Where am I: switching scenes, tabs in a panel, sport categories (ink capsule) |
| `TabBar` | The app's floating glass tab bar |
| `PickRow`, `PickPill`, `PickTile`, `Swatch`, `CheckBadge` | What did I pick: white with a hairline; picked, a 1.5 stroke and a check in the accent tone |
| `InputField`, `SearchField` | Text entry |
| `KindButton`, `Tag`, `CheckInBurst` | The four check-in kinds; the 打卡 button and its capsules |
| `SquadCard`, `StatusRing`, `Score`, `ProgressBar`, `PlusOne` | The home card swiped between the squad's week and my week; today's rings; Barlow numbers; the 「+1」 pop |
| `.card(on:)`, `SectionLabel`, `ListRow`, `SwitchRow` | Cards (grey on a page, white on the scene), group labels, list rows, a setting's on/off row |
| `SpeechBubble`, `SceneFloor`, `CharacterStage` | What the character says (with an action, a button that opens it); the scene's floor behind sign-up; the character's stage in the editor |

Conventions, as SwiftUI's own controls do it: the label comes first (`Text`, so it goes through the String Catalog), state comes in as a value (`isSelected`, `status`) and changes go out through an `action` closure or a `Binding`; button variants are `ButtonStyle`s; the scene and the accent tone come from the environment (`\.sceneTheme`, `\.accentTone`); UI-test identifiers are set by the caller. Each component's doc comment says when to use it and what its states look like, and the style guide shows every state.

## Haptics

One meaningful tap per moment, never a buzz (Apple HIG, Playing haptics). Screens call `.haptic(_:trigger:)`; iOS skips it when system haptics are off.

| `Haptic` | Moment |
| --- | --- |
| `pick` | Picking an option, swatch, tab or style |
| `appear` | The check-in capsules opening, drafts landing |
| `refuse` | Tapping a kind that can't be used today |
| `tick`, `checkIn` | My own status ring drawing (ticks), then closing (one heavy hit, the check-in's only one) |
| `score` | The score turning over |
| `land` | The character landing after 上场 |
| `reaction` | A teammate's reaction arriving |

## Adding to it

- **Reuse first.** Look here before building a piece of UI.
- **Generic or used on two screens: it belongs here.** A piece one screen alone needs (the home scene's layout, confetti) can stay with that screen, built only from tokens. When a second screen needs it, move it here.
- **New look, canvas first.** A new component or variant is drawn on the v4 canvas (or is in an approved screen) before it is coded here. Name it for what it is for, document it, and add it to the style guide.
- **Enforced:** SwiftLint (`.swiftlint.yml`) rejects a raw color, `Palette`, a numeric radius or spacing, a system text style, or a haptic that isn't a `Haptic` outside this package; tests pin every token value to the canvas.
