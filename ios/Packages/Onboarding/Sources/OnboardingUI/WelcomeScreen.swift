#if os(iOS)
import AvatarUI
import DesignSystem
import DesignSystemUI
import OnboardingDomain
import SwiftUI

/// The open screen: the app's name, one line, and five characters on the gym's floor, two at
/// the back and three in front, the middle one biggest. On the first open WILDCARD sprints in
/// and breaks the finish tape while the squad watches; they cheer, then each does a check-in
/// once. Every so often one of them changes into another look, and a tap changes it too. The
/// middle one's look is where 角色和昵称 starts. Then 通过 Apple 继续, and the terms under it.
struct WelcomeScreen<SignIn: View>: View {
    let model: SignUpModel
    let policies: PolicyLinks
    let signIn: SignIn
    /// The open screen is the gym's, like the website, whatever the squad's scene.
    private let theme = SceneTheme.gym
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("welcome.sprintPlayed") private var sprintPlayed = false
    @State private var crowd = WelcomeCrowd()
    @State private var word: CGRect?
    @State private var sprint: SprintRunner?
    /// The word stands at its place (no sprint, or it has finished).
    @State private var settled = false
    /// The slogan and the button are up.
    @State private var revealed = false
    @State private var landed = 0
    @State private var homeIndicator = 0.0

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / WelcomeCrowd.designWidth
            let top = proxy.safeAreaInsets.top
            ZStack(alignment: .top) {
                WelcomeFloor(theme: theme)
                    .frame(height: WelcomeCrowd.floorAbove * unit)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                if let sprint {
                    // The tape, from above the screen's top down to the floor.
                    FinishTape(runner: sprint, theme: theme)
                        .frame(width: proxy.size.width, height: proxy.size.height + top)
                        .offset(y: -top)
                }
                ForEach(crowd.spots.indices, id: \.self) { index in
                    crowdMember(index, unit: unit, bottom: proxy.size.height)
                }
                title(top: WelcomeCrowd.titleTop)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .coordinateSpace(.named(Self.space))
            .task(id: word.map { Self.layout(word: $0, top: top, height: proxy.size.height, unit: unit) }) {
                guard let word else { return }
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
            .modifier(Reveal(shown: revealed, delay: WelcomeCrowd.buttonDelay, reduceMotion: reduceMotion))
        }
        .background {
            // Reaching under the home indicator, the page knows how tall it is.
            Color(role: .bgBrand, in: theme)
                .ignoresSafeArea()
                .onGeometryChange(for: Double.self) {
                    $0.safeAreaInsets.bottom
                } action: {
                    homeIndicator = $0
                }
        }
        .environment(\.sceneTheme, theme)
        .haptic(.land, trigger: landed)
        .onDisappear { crowd.stop() }
        .onChange(of: crowd.middleLook) { _, look in model.welcomeLook = look }
    }

    private static let space = "welcome"
    /// The capitals' top and the baseline, from the middle of the word's glyphs.
    private static let capTop = -21.0
    private static let baseline = 22.0

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
                    $0.frame(in: .named(Self.space))
                } action: {
                    word = $0
                }
                .modifier(
                    Sprinting(runner: sprint, settled: settled, baseline: (word?.height ?? 0) / 2 + Self.baseline)
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
            wordRight: word.maxX, capTop: top + word.midY + capTop, baseline: top + word.midY + baseline,
            floorTop: top + height - WelcomeCrowd.floorAbove * unit)
    }

    /// The first open plays the sprint, timed so the haptic, the cheer and the reveal land on
    /// the break; later opens, and Reduce Motion, start at the still screen.
    private func open(layout: FinishLineSprint.Layout) async {
        guard !settled, sprint == nil else { return }
        guard !reduceMotion, !sprintPlayed else {
            settled = true
            revealed = true
            await crowd.load(reduceMotion: reduceMotion)
            crowd.play(sprinting: false)
            return
        }
        // The squad is on its spots before the word comes in; a new layout starts over.
        await crowd.load(reduceMotion: reduceMotion)
        guard !Task.isCancelled else { return }
        sprintPlayed = true
        let timing = FinishLineSprint.timing(for: layout)
        let start = ContinuousClock.now
        sprint = SprintRunner(layout: layout)
        try? await Task.sleep(until: start + .seconds(timing.breaks), clock: .continuous)
        landed += 1
        crowd.play(sprinting: true)
        try? await Task.sleep(until: start + .seconds(timing.breaks + WelcomeCrowd.revealDelay), clock: .continuous)
        revealed = true
        try? await Task.sleep(until: start + .seconds(timing.ends), clock: .continuous)
        settled = true
        sprint = nil
    }

    /// 继续即表示同意用户协议和隐私政策, with 用户协议 and 隐私政策 underlined links to their pages.
    /// The catalog marks them `terms:` and `privacy:`, which become the pages the app passes.
    private var termsLine: AttributedString {
        var line = AttributedString(
            localized: "继续即表示同意[用户协议](terms:)和[隐私政策](privacy:)", bundle: .module)
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
        .accessibilityLabel(Text("换一个小人", bundle: .module))
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
                .animation(.wildcard(Motion.page, reduceMotion: true), value: settled)
        }
    }

    /// A skew about the baseline, `degrees` from upright: the top runs ahead of the feet.
    private static func lean(_ degrees: Double, baseline: Double) -> CGAffineTransform {
        let slope = tan(degrees * .pi / 180)
        return CGAffineTransform(a: 1, b: 0, c: slope, d: 1, tx: -slope * baseline, ty: 0)
    }
}

/// The finish tape in the accent, round at its ends, fading once it has fallen.
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
                    path, with: .color(Color(role: .bgAccent, in: theme)),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Rises 8 points and fades in once shown, after `delay`; with Reduce Motion it only fades.
private struct Reveal: ViewModifier {
    let shown: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .animation(.wildcard(Motion.page, reduceMotion: reduceMotion).delay(delay), value: shown)
    }
}

/// The open screen's floor: light grey, with the gym's graphite and volt stripe along its top
/// and faint tiles, as on the website. The gym's own floor is dark, so this one is drawn here.
private struct WelcomeFloor: View {
    let theme: SceneTheme
    /// The tiles' side, in points.
    private static let tile = 65.0
    /// The first row of tiles, under the floor's stripe.
    private static let firstRow = 64.0

    var body: some View {
        ZStack(alignment: .top) {
            Color(role: .bgBrandFloor, in: theme)
            Canvas { context, size in
                var path = Path()
                for column in stride(from: Self.tile, to: size.width, by: Self.tile) {
                    path.move(to: CGPoint(x: column, y: 0))
                    path.addLine(to: CGPoint(x: column, y: size.height))
                }
                for row in stride(from: Self.firstRow, to: size.height, by: Self.tile) {
                    path.move(to: CGPoint(x: 0, y: row))
                    path.addLine(to: CGPoint(x: size.width, y: row))
                }
                context.stroke(path, with: .color(Color(role: .borderBrandFloor, in: theme)), lineWidth: 1.5)
            }
            VStack(spacing: 0) {
                Color(role: .bgAccent, in: theme).frame(height: 4)
                Color(role: .fgOnAccent, in: theme).frame(height: 3)
            }
        }
        .accessibilityHidden(true)
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
