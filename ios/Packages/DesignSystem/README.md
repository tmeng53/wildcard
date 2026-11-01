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
| `PrimaryButtonStyle`, `SecondaryButtonStyle`, `TextButtonStyle` | The one primary action (52, the accent tone: scene, brand, or ink on the 我 pages), a second action (44, grey; white inside a grey card), a quiet text action; `.danger` turns only the words red (`fgDanger`), for an action that can't be taken back (解雇), never the page's main action |
| `AppleButtonStyle` | Confirming with Apple (注销), in Apple's own black as its button guidelines ask: filled, or `.outlined` when a gentler action leads |
| `HeaderButton`, `StepHeader`, `StepSegments` | A 44-point round header button in the system's interactive Liquid Glass on every surface (a white glyph over photos on ink); a sign-up step's back button and ink segments |
| `.photoViewer(isPresented:count:page:load:)` | A post's photos full screen on ink, zooming out of the photos tapped: pinch or double tap to zoom, swipe between them, swipe down or 关闭 to put them back (发动态 and 动态) |
| `swipesBack(isEnabled:perform:)` | A page with 返回 also goes back on a swipe right from anywhere on it, following the finger |
| `CategoryBar` | Where am I: switching scenes, tabs in a panel, sport categories (ink capsule) |
| `AppTabs`, `TabBarItem` | The app's tabs in the system's own Liquid Glass tab bar, the selected tab in ink |
| `PickRow`, `PickPill`, `PickTile`, `Swatch`, `CheckBadge` | What did I pick: white with a hairline; picked, a 1.5 stroke and a check in the accent tone; a `.solid` `PickPill` fills with the accent tone instead (发动态's sport) |
| `TickRuler`, `RulerScale` | A number slid under a needle (刻度), snapping to the scale's marks with one `pick` tick per mark (发动态's minutes under 其他) |
| `InputField`, `SearchField` | Text entry |
| `dismissesKeyboardOnTapOutside()` | Applied once at the app's root: a tap outside a text input puts the keyboard away on every screen, and still reaches what was tapped |
| `KindButton`, `Tag`, `CheckInBurst` | The four check-in kinds; the 打卡 button and its capsules |
| `SquadCard`, `StatusRing`, `Score`, `ProgressBar`, `PlusOne` | The home card swiped between the squad's week and my week; today's rings; Barlow numbers; the 「+1」 pop |
| `TicketSpinner`, `TicketRock` | A whole-page wait: the logo's two tickets rocking apart and back on a 0.9 s beat, on graphite (`.brand`, the launch cover) or the brand's light page (`.page`); still with Reduce Motion |
| `.card(on:)`, `SectionLabel`, `ListRow`, `SwitchRow` | Cards (grey on a page, white on the scene), group labels, list rows (a plain menu leaves out icon and chevron), a setting's on/off row |
| `SceneTile`, `CartonBox`, `Tween`, `Wiggle` | A scene to pick for next week (a colour pattern card once the squad has trained there, a kraft carton until then, shaking every 2.4 s while picked); the carton the reveal opens; the reveal's easing curves |
| `PullCord`, `PullCordMotion` | The light switch hanging under the home's card at night: a ball chain and a bulb, white when off, warm when on; pulled down it clicks at 24 points, springs back and swings |
| `SpeechBubble`, `CharacterStage` | What the character says (with an action, a button that opens it; `.quote` for a line that must show whole, like a coach's catchphrase); the character's ticket in the editor (sign-up and 我), in the brand's colours under a flat spotlight, never the scene's |
| `LoadingDots`, `.loadingLabel(_:)`, `.loadingCover(_:loader:)`, `LoadingSwap` | Waiting (三拍, loader design A): three dots hopping in the colour around them for a button or a line, shown only after `Loading.inlineDelay` and kept `Loading.minimumShown`; a whole page waits under a cover, `AvatarUI`'s `LoadingCharacter` jogging in place, after `Loading.pageDelay`. No words, ever |
| `WeekPoster`, `WeekPosterLayout` | The week as a poster: name and dates, the big italic W43, a row a day, the character in the corner and a strip along the bottom. `.card` is sign-up's 本周目标 (the page's width, in the brand), `.poster` the 出赛表's 3:4 picture (in the scene); the screen draws the rows, the strip's content and the character |

Conventions, as SwiftUI's own controls do it: the label comes first (`Text`, so it goes through the String Catalog), state comes in as a value (`isSelected`, `status`) and changes go out through an `action` closure or a `Binding`; button variants are `ButtonStyle`s; the scene and the accent tone come from the environment (`\.sceneTheme`, `\.accentTone`); UI-test identifiers are set by the caller. Each component's doc comment says when to use it and what its states look like, and the style guide shows every state.

## Haptics

One meaningful tap per moment, never a buzz (Apple HIG, Playing haptics). Screens call `.haptic(_:trigger:)`; iOS skips it when system haptics are off.

| `Haptic` | Moment |
| --- | --- |
| `pick` | Picking an option, swatch, tab or style; each mark passing a `TickRuler`'s needle |
| `appear` | The check-in capsules opening, drafts landing |
| `refuse` | Tapping a kind that can't be used today |
| `tick`, `checkIn` | My own status ring drawing (ticks), then closing (one heavy hit, the check-in's only one) |
| `score` | The score turning over |
| `land` | The character landing after 上场 |
| `crown` | The crown landing on the 战报 champion |
| `reaction` | A teammate's reaction arriving |
| `unbox` | The flaps flying off a new scene's carton (the scene pick's only one) |
| `lights` | The pull cord clicking the lights on at night (none when they go off) |

## Adding to it

- **Reuse first.** Look here before building a piece of UI.
- **Generic or used on two screens: it belongs here.** A piece one screen alone needs (the home scene's layout, confetti) can stay with that screen, built only from tokens. When a second screen needs it, move it here.
- **New look, canvas first.** A new component or variant is drawn on the v4 canvas (or is in an approved screen) before it is coded here. Name it for what it is for, document it, and add it to the style guide.
- **Enforced:** SwiftLint (`.swiftlint.yml`) rejects a raw color, `Palette`, a numeric radius or spacing, a system text style, or a haptic that isn't a `Haptic` outside this package; tests pin every token value to the canvas.
