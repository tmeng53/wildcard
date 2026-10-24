#if os(iOS)
import CheckInUI
import DesignSystem
import DesignSystemUI
import RecapDomain
import ScenePickDomain
import ScenePickUI
import SwiftUI

/// The Sunday 战报, full screen: one page at a time with a segment bar on top, like a phone
/// story. Tap the right of the screen to go on, the left to go back; hold to pause; swipe down
/// or ✕ to close. It takes the squad's scene colors for that week.
public struct RecapView: View {
    /// The picked scene coming out of its box, over the last page.
    private struct Reveal {
        let unboxing: Unboxing
        let scene: SceneTheme
        let startedAt: Date
        var heldAt: Double?
    }

    let model: RecapModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var picture: Image?
    @State private var dragDown = 0.0
    @State private var touchedAt: Date?
    @State private var reveal: Reveal?

    private let autoAdvances: Bool

    /// - Parameter autoAdvances: false for UI tests, which move on by tapping.
    public init(model: RecapModel, autoAdvances: Bool = true) {
        self.model = model
        self.autoAdvances = autoAdvances
        _reveal = State(
            initialValue: model.heldReveal.map { held in
                let opened = model.scenePicker?.options.first { $0.scene == held.scene }?.isOpened ?? false
                return Reveal(unboxing: Unboxing(boxed: !opened), scene: held.scene, startedAt: .now, heldAt: held.at)
            })
    }

    public var body: some View {
        ZStack {
            story
                // Under the reveal the page is a picture: no taps, nothing for VoiceOver.
                .allowsHitTesting(reveal == nil)
                .accessibilityHidden(reveal != nil)
            if let reveal {
                UnboxRevealView(
                    reveal.unboxing, scene: reveal.scene, startedAt: reveal.startedAt, frozenAt: reveal.heldAt,
                    onFinished: { model.revealed(reveal.scene, coveredAt: $0) },
                    page: { endingStill(actions: true) },
                    backdrop: { SceneBackdrop(scene: reveal.scene) })
            }
        }
        .onChange(of: voiceOver, initial: true) { _, isOn in model.autoAdvance(!isOn && autoAdvances) }
        .environment(\.sceneTheme, model.cast.scene)
        .statusBarHidden()
        .task { picture = await renderPicture() }
        // Drawn again on the ending if the first try came back empty.
        .task(id: model.onLastPage) {
            if model.onLastPage, picture == nil { picture = await renderPicture() }
        }
    }

    private var story: some View {
        TimelineView(.animation(minimumInterval: nil, paused: false)) { timeline in
            let frame = model.frame(at: timeline.date)
            let context = PageContext(
                time: frame.elapsed, moves: !reduceMotion, story: model.story, cast: model.cast,
                wardrobe: model.wardrobe)
            ZStack(alignment: .top) {
                Color(role: .bgScene, in: model.cast.scene).ignoresSafeArea()
                page(model.pages[frame.index], context: context)
                    .id(frame.index)
                    .padding(.top, Self.chromeHeight)
                chrome(segments: model.segments(at: timeline.date))
            }
            .onChange(of: frame.index) { _, _ in model.tick(timeline.date) }
        }
        .offset(y: max(dragDown, 0))
        .contentShape(Rectangle())
        .gesture(touch)
        .accessibilityAction(named: Text("下一页", bundle: .module)) { model.next() }
        .accessibilityAction(named: Text("上一页", bundle: .module)) { model.previous() }
    }

    /// One touch does it all, as a phone story: touching pauses the page; a quick tap on the
    /// left third goes back and anywhere else goes on; a pull down closes.
    private var touch: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if touchedAt == nil {
                    touchedAt = drag.time
                    model.hold(true)
                }
                dragDown = drag.translation.height
            }
            .onEnded { drag in
                let held = drag.time.timeIntervalSince(touchedAt ?? drag.time)
                touchedAt = nil
                model.hold(false)
                withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { dragDown = 0 }
                if drag.translation.height > Self.closeDistance {
                    model.dismiss()
                } else if held < Self.tapLength, abs(drag.translation.width) < Space.s,
                    abs(drag.translation.height) < Space.s
                {
                    if drag.location.x < Self.backZone { model.previous() } else { model.next() }
                }
            }
    }

    private func chrome(segments: [Double]) -> some View {
        VStack(spacing: Space.s) {
            SegmentBar(fractions: segments)
            HStack(spacing: Space.xs) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: model.story.squadName).typeStyle(TypeRamp.calloutEmphasis)
                    Text(verbatim: model.story.week.label).typeStyle(TypeRamp.footnote)
                }
                .foregroundStyle(Color(role: .fgOnScene, in: model.cast.scene))
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                HeaderButton(Text("关闭", bundle: .module), systemImage: "xmark", on: .scene) { model.dismiss() }
                    .accessibilityIdentifier("recap.close")
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.top, Space.xs)
    }

    @ViewBuilder
    private func page(_ page: StoryPage, context: PageContext) -> some View {
        switch page {
        case .pending:
            PendingPage(page: context, nudged: model.nudged, nudge: model.nudge)
                .storyPage("pending")
        case .podium(let podium): PodiumPage(podium: podium, page: context).storyPage("podium")
        case .titles(let rows): TitlesPage(rows: rows, page: context).storyPage("titles")
        case .myWeek(let week): MyWeekPage(week: week, page: context).storyPage("myWeek")
        case .hottest(let hottest):
            HottestPage(hottest: hottest, page: context).storyPage("hottest")
        case .meals(let meals): MealsPage(meals: meals, page: context).storyPage("meals")
        case .bestDisclaimer(let note):
            BestDisclaimerPage(note: note, page: context).storyPage("bestDisclaimer")
        case .ending(let ending):
            self.ending(
                ending, context: context, actions: EndingActions(picture: picture, planNextWeek: model.planNextWeek)
            )
            .storyPage("ending")
        }
    }

    /// The last page, with 冠军专属's sticker for whoever picks next week's scene.
    @ViewBuilder
    private func ending(_ ending: Ending, context: PageContext, actions: EndingActions?) -> some View {
        if let actions, let picker = model.scenePicker {
            EndingPickPage(ending: ending, page: context, actions: actions, picker: picker) { unboxing, scene in
                reveal = Reveal(unboxing: unboxing, scene: scene, startedAt: .now)
            }
        } else {
            EndingPage(ending: ending, page: context, actions: actions)
        }
    }

    /// The last page as it settles: under the reveal, with its header and buttons, and in 存图's
    /// picture, without them or the sticker.
    private func endingStill(actions: Bool) -> some View {
        ZStack(alignment: .top) {
            Color(role: .bgScene, in: model.cast.scene)
            if case .ending(let ending)? = model.pages.last {
                let context = PageContext(
                    time: ending.isHit ? 3 : 2.4, moves: true, story: model.story, cast: model.cast,
                    wardrobe: model.wardrobe)
                self.ending(
                    ending, context: context,
                    actions: actions ? EndingActions(picture: picture, planNextWeek: model.planNextWeek) : nil
                )
                .padding(.top, Self.chromeHeight)
            }
            if actions { chrome(segments: model.pages.map { _ in 1 }) }
        }
        .environment(\.sceneTheme, model.cast.scene)
    }

    /// The ending as it settles, drawn once to a picture for 存图: the squad's week, the count
    /// and everyone's finale, without the buttons.
    private func renderPicture() async -> Image? {
        guard case .ending? = model.pages.last else { return nil }
        let card = endingStill(actions: false)
            .frame(width: Self.pictureSize.width, height: Self.pictureSize.height)
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(Self.pictureSize)
        renderer.scale = Self.pictureScale
        if let image = renderer.uiImage { return Image(uiImage: image) }
        return renderer.cgImage.map { Image(decorative: $0, scale: Self.pictureScale) }
    }

    /// Room for the segments and the header above each page.
    static let chromeHeight: Double = 64
    private static let backZone: Double = 120
    private static let closeDistance: Double = 120
    /// Longer than this, a touch was a hold, not a tap.
    private static let tapLength: TimeInterval = 0.25
    /// 存图 draws a phone-sized picture, sharp enough to post.
    private static let pictureSize = CGSize(width: 390, height: 844)
    private static let pictureScale: Double = 3
}

/// One thin segment per page: done, filling, to come.
private struct SegmentBar: View {
    let fractions: [Double]
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(spacing: Space.xxs) {
            ForEach(fractions.indices, id: \.self) { index in
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color(role: .fgOnScene, in: theme).opacity(0.15))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color(role: .fgOnScene, in: theme))
                                .frame(width: proxy.size.width * fractions[index])
                        }
                }
                .frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("第 \(currentPage) 页，共 \(fractions.count) 页", bundle: .module))
    }

    private var currentPage: Int {
        (fractions.firstIndex { $0 < 1 } ?? fractions.count - 1) + 1
    }
}

extension View {
    /// Names a page for UI tests as a container, so the buttons on it keep their own names.
    fileprivate func storyPage(_ name: String) -> some View {
        accessibilityElement(children: .contain).accessibilityIdentifier("recap.page.\(name)")
    }
}
#endif
