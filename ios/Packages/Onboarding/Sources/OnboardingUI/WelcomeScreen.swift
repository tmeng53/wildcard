#if os(iOS)
import AvatarUI
import DesignSystem
import DesignSystemUI
import OnboardingDomain
import SwiftUI

/// The open screen: the app's name, one line, and five characters on a light floor, two at
/// the back and three in front, the middle one biggest. Each time the screen opens (the app
/// starts, comes back from the background, or sign-up steps back to it) WILDCARD sprints in
/// and breaks the finish tape while the squad watches; they cheer, then each does a check-in
/// once. Every so often one of them changes into another look, and a tap changes it too. The
/// middle one's look is where 角色和昵称 starts. Then 通过 Apple 继续, and the terms under it.
/// The globe in the top corner picks the app's language before signing up.
struct WelcomeScreen<SignIn: View>: View {
    let model: SignUpModel
    let policies: PolicyLinks
    let signIn: SignIn
    /// The open screen wears the brand, like the website, whatever the squad's scene; the
    /// roles it draws with are fixed, so the scene only fills in the signature.
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var picksLanguage = false
    @State private var crowd = WelcomeCrowd()
    @State private var word: CGRect?
    @State private var sprint: SprintRunner?
    /// The word stands at its place (no sprint, or it has finished).
    @State private var settled = false
    /// The slogan and the button are up.
    @State private var revealed = false
    @State private var landed = 0
    @State private var homeIndicator = 0.0
    /// How many times the screen has opened again from the background; each plays the sprint.
    @State private var reopens = 0
    /// In the background, where nothing plays.
    @State private var away = false

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / WelcomeCrowd.designWidth
            let top = proxy.safeAreaInsets.top
            ZStack(alignment: .top) {
                BrandFloor(theme: theme)
                    .frame(height: WelcomeCrowd.floorAbove * unit)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                if let sprint {
                    // The tape, from above the screen's top down to the floor. It reaches past
                    // the top inside a frame of the screen's own height, so the stack keeps its
                    // size: a taller stack is centred in its frame, which lifted the floor and
                    // the squad by half the status bar until the tape went and they dropped back.
                    FinishTape(runner: sprint, theme: theme)
                        .frame(width: proxy.size.width, height: proxy.size.height + top)
                        .frame(height: proxy.size.height, alignment: .bottom)
                }
                ForEach(crowd.spots.indices, id: \.self) { index in
                    crowdMember(index, unit: unit, bottom: proxy.size.height)
                }
                title(top: WelcomeCrowd.titleTop)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay(alignment: .topTrailing) { language }
            .coordinateSpace(.named(WelcomeTitle.space))
            // Once the word is measured, from where it stands then, and again on each reopen;
            // going to the background cancels it. Keyed on the layout, the sprint restarted
            // forever: the word is measured again as the sprint takes it over.
            .task(id: word == nil || away ? -1 : reopens) {
                guard let word, !away else { return }
                await open(layout: Self.layout(word: word, top: top, height: proxy.size.height, unit: unit))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Space.s) {
                FailureLine(failure: model.failure)
                signIn
                    .frame(height: Sizing.primaryControl)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("signup.signIn")
                Text(termsLine)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .tint(Color(role: .fgDefault, in: theme))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("signup.terms")
            }
            .padding(.horizontal, Space.pageMargin)
            // Phones with a home indicator sit the terms right on it, as the design does.
            .padding(.bottom, homeIndicator > 0 ? 0 : Space.xs)
            .modifier(Reveal(shown: revealed, delay: Motion.revealStagger, reduceMotion: reduceMotion))
        }
        .background {
            // Reaching under the home indicator, the page knows how tall it is.
            Color(role: .bgBrandPage, in: theme)
                .ignoresSafeArea()
                .onGeometryChange(for: Double.self) {
                    $0.safeAreaInsets.bottom
                } action: {
                    homeIndicator = $0
                }
        }
        .haptic(.land, trigger: landed)
        .onDisappear { crowd.stop() }
        .onChange(of: scenePhase) { _, phase in reopen(phase) }
        .onChange(of: crowd.middleLook) { _, look in model.welcomeLook = look }
    }

    /// The globe that picks the app's language, before signing up.
    private var language: some View {
        HeaderButton(Text("语言", bundle: .module), systemImage: "globe", on: .scene) { picksLanguage = true }
            .padding(.trailing, Space.pageMargin)
            .accessibilityIdentifier("signup.language")
            .languagePicker(isPresented: $picksLanguage)
    }

    /// WILDCARD, then the slogan under it. While the sprint plays the word is drawn where the
    /// sprint has it; its place is measured first, standing still and unseen.
    private func title(top: Double) -> some View {
        VStack(spacing: Space.s) {
            // The word's glyphs centered on a 60-point line, as the design sets them.
            Text("WILDCARD", bundle: .module)
                .typeStyle(TypeRamp.scoreHero)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .fixedSize()
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named(WelcomeTitle.space))
                } action: {
                    word = $0
                }
                .modifier(
                    Sprinting(
                        runner: sprint, settled: settled, baseline: (word?.height ?? 0) / 2 + WelcomeTitle.baseline)
                )
                .frame(height: WelcomeCrowd.wordLine)
            Text("人人都是运动员", bundle: .module)
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .modifier(Reveal(shown: revealed, delay: 0, reduceMotion: reduceMotion))
        }
        .padding(.top, top)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Where the sprint runs: the word's place and the floor, from the screen's top edge.
    private static func layout(word: CGRect, top: Double, height: Double, unit: Double) -> FinishLineSprint.Layout {
        FinishLineSprint.Layout(
            wordRight: word.maxX, capTop: top + word.midY + WelcomeTitle.capTop,
            baseline: top + word.midY + WelcomeTitle.baseline,
            floorTop: top + height - WelcomeCrowd.floorAbove * unit)
    }

    /// Going to the background puts the screen back before the sprint, out of sight; coming
    /// back plays it again. A sheet over the screen (Sign in with Apple) only makes it
    /// inactive, so it doesn't replay.
    private func reopen(_ phase: ScenePhase) {
        switch phase {
        case .background:
            crowd.stop()
            away = true
            sprint = nil
            settled = false
            revealed = false
        case .active where away:
            away = false
            reopens += 1
        default:
            break
        }
    }

    /// Each open plays the sprint, timed so the haptic, the cheer and the reveal land on the
    /// break; Reduce Motion starts at the still screen.
    private func open(layout: FinishLineSprint.Layout) async {
        guard !settled, !reduceMotion else {
            // Still, or the layout changed after the sprint: the squad plays on where it stands.
            settled = true
            revealed = true
            await crowd.load(reduceMotion: reduceMotion)
            crowd.play(sprinting: false)
            return
        }
        // The squad is on its spots before the word comes in; coming back before the break
        // starts over, and after it lets the screen settle.
        await crowd.load(reduceMotion: reduceMotion)
        guard !Task.isCancelled else { return }
        // Played through off the main actor, so the first frame of the sprint isn't held up.
        let timing = await Task.detached { FinishLineSprint.timing(for: layout) }.value
        guard !Task.isCancelled else { return }
        let start = ContinuousClock.now
        let runner = SprintRunner(layout: layout)
        sprint = runner
        guard await wait(until: start + .seconds(timing.breaks), runner) else { return }
        landed += 1
        crowd.play(sprinting: true)
        guard await wait(until: start + .seconds(timing.breaks + WelcomeCrowd.revealDelay), runner) else { return }
        revealed = true
        guard await wait(until: start + .seconds(timing.ends), runner) else { return }
        settled = true
        sprint = nil
    }

    /// Waits until `deadline`; false when the screen moved on or went to the background (a task
    /// asleep through a suspension can wake before it is cancelled), taking `runner` down
    /// unless a newer layout's sprint has already replaced it.
    private func wait(until deadline: ContinuousClock.Instant, _ runner: SprintRunner) async -> Bool {
        try? await Task.sleep(until: deadline, clock: .continuous)
        guard Task.isCancelled || away else { return true }
        if sprint === runner { sprint = nil }
        return false
    }

    /// 继续即表示同意用户协议和隐私政策, with 用户协议 and 隐私政策 underlined links to their pages.
    /// The catalog marks them `terms:` and `privacy:`, which become the pages the app passes.
    private var termsLine: AttributedString {
        var line = AttributedString(
            localized: "继续即表示同意[用户协议](terms:)和[隐私政策](privacy:)", bundle: .module.inAppLanguage)
        for (link, range) in line.runs[\.link] {
            guard let link else { continue }
            line[range].link = link.scheme == "terms" ? policies.terms : policies.privacyPolicy
            line[range].underlineStyle = .single
        }
        return line
    }

    private func crowdMember(_ index: Int, unit: Double, bottom: Double) -> some View {
        let spot = crowd.spots[index]
        let width = spot.width * unit
        let height = width * WelcomeCrowd.aspect
        let feet = bottom - spot.feetAbove * unit
        return Button {
            crowd.swap(index)
        } label: {
            ZStack {
                if let player = crowd.players[index] {
                    CharacterView(player: player)
                        .id(crowd.versions[index])
                        .transition(
                            reduceMotion ? .opacity : .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
                }
                if crowd.dozing[index] {
                    DozeZ(started: crowd.dozedAt[index])
                }
            }
            .frame(width: width, height: height)
            .animation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion), value: crowd.versions[index])
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("换一个外卡运动员", bundle: .module))
        .accessibilityIdentifier("signup.crowd")
        .haptic(.pick, trigger: crowd.taps[index])
        // Feet on the floor: the canvas's feet sit near its bottom.
        .position(x: spot.centerX * unit, y: feet - height * WelcomeCrowd.feetInCanvas + height / 2)
        // Nearer the front draws on top, and everyone over the floor (zIndex 0).
        .zIndex(1 / (1 + spot.feetAbove))
    }
}

/// The sprint as it plays, advanced to each frame's time. Both the word and the tape ask it for
/// the same moment in a frame, so it steps once.
@MainActor
final class SprintRunner {
    private var sprint: FinishLineSprint
    private let start = Date.now

    init(layout: FinishLineSprint.Layout) {
        sprint = FinishLineSprint(layout: layout)
    }

    func at(_ date: Date) -> FinishLineSprint {
        sprint.advance(to: date.timeIntervalSince(start))
        return sprint
    }
}

/// The word where the sprint has it: moved, lifted by its stride and leaning about its
/// baseline. Hidden until the sprint starts; with Reduce Motion it fades in at its place.
private struct Sprinting: ViewModifier {
    let runner: SprintRunner?
    let settled: Bool
    /// How far down the word its baseline is.
    let baseline: Double

    func body(content: Content) -> some View {
        if let runner {
            TimelineView(.animation) { context in
                let sprint = runner.at(context.date)
                content
                    .transformEffect(Self.lean(sprint.lean, baseline: baseline))
                    .offset(x: sprint.offset, y: sprint.lift)
            }
        } else {
            content
                .opacity(settled ? 1 : 0)
                .animation(.wildcard(Motion.fadeIn), value: settled)
        }
    }

    /// A skew about the baseline, `degrees` from upright: the top runs ahead of the feet.
    private static func lean(_ degrees: Double, baseline: Double) -> CGAffineTransform {
        let slope = tan(degrees * .pi / 180)
        return CGAffineTransform(a: 1, b: 0, c: slope, d: 1, tx: -slope * baseline, ty: 0)
    }
}

/// The finish tape in the brand colour, round at its ends, fading once it has fallen.
private struct FinishTape: View {
    let runner: SprintRunner
    let theme: SceneTheme

    var body: some View {
        TimelineView(.animation) { context in
            let sprint = runner.at(context.date)
            Canvas { canvas, _ in
                var path = Path()
                for piece in sprint.tapePieces {
                    guard let first = piece.first else { continue }
                    path.move(to: CGPoint(x: first.x, y: first.y))
                    for point in piece.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
                }
                canvas.opacity = sprint.tapeOpacity
                canvas.stroke(
                    path, with: .color(Color(role: .bgBrand, in: theme)),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Rises and fades in once shown, after `delay`; with Reduce Motion it only fades.
private struct Reveal: ViewModifier {
    let shown: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : Motion.revealRise)
            .animation(.wildcard(Motion.reveal).delay(delay), value: shown)
    }
}

/// The 请假条's nap: a "z" floating up from the head, again and again while the nap lasts.
private struct DozeZ: View {
    let started: Date
    @Environment(\.sceneTheme) private var theme
    /// One z's rise, in seconds.
    private static let period = 1.6

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 240
            TimelineView(.animation) { context in
                let rise =
                    context.date.timeIntervalSince(started).truncatingRemainder(dividingBy: Self.period) / Self.period
                Text(verbatim: "z")
                    .typeStyle(TypeRamp.scoreHero)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .scaleEffect((40 + 16 * rise) / 60 * unit)
                    .opacity(sin(.pi * rise))
                    .position(x: (168 + 22 * rise) * unit, y: (82 - 60 * rise) * unit)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif

/// The open screen's coordinate space and the word's metrics, outside the generic view, which
/// can't hold static stored properties.
private enum WelcomeTitle {
    static let space = "welcome"
    /// The capitals' top and the baseline, from the middle of the word's glyphs.
    static let capTop = -21.0
    static let baseline = 22.0
}
