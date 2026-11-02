#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// A post's face where it has no photo, and the same corners over a photo where it has one: a
/// block in its sport's scene colour with the post's words on it, the sport or kind top right,
/// a 练了's minutes bottom left and, on a tile, its day top left. Every screen that shows a post
/// without a photo draws this one block: 我的动态's tiles, 动态's cards and the 战报's
/// 你最火的一条 (Tracy, 2026-11-02).
public struct PostBlock: View {
    /// Where the block sits, which sets its type and padding; the caller gives the frame.
    public enum Layout: Sendable {
        /// A square on 我的动态's wall.
        case tile
        /// A wide strip in place of a 动态 card's photos.
        case strip
        /// The 战报's tall card.
        case card
    }

    private let kind: CheckInKind
    private let activity: Activity?
    private let words: String?
    private let minutes: Int?
    private let day: Int?
    private let photo: Image?
    private let layout: Layout

    /// `activity` is a 练了's sport; `day` (the day of the month) shows top left where given;
    /// with a `photo` the block is that photo and leaves its words to the caller.
    public init(
        kind: CheckInKind, activity: Activity? = nil, words: String? = nil, minutes: Int? = nil, day: Int? = nil,
        photo: Image? = nil, layout: Layout
    ) {
        self.kind = kind
        self.activity = activity
        self.words = words
        self.minutes = minutes
        self.day = day
        self.photo = photo
        self.layout = layout
    }

    /// A check-in's block: its kind, sport, words and minutes.
    public init(checkIn: CheckIn, day: Int? = nil, photo: Image? = nil, layout: Layout) {
        switch checkIn.entry {
        case .trained(let training):
            self.init(
                kind: .trained, activity: training.activity, words: training.caption?.text,
                minutes: training.minutes?.value, day: day, photo: photo, layout: layout)
        case .healthyMeal(let meal):
            self.init(kind: .healthyMeal, words: meal.caption?.text, day: day, photo: photo, layout: layout)
        case .cheatMeal(let meal):
            self.init(kind: .cheatMeal, words: meal.caption?.text, day: day, photo: photo, layout: layout)
        case .disclaimer(let disclaimer):
            self.init(kind: .disclaimer, words: disclaimer.text, day: day, photo: photo, layout: layout)
        }
    }

    public var body: some View {
        let colors = PostBlockColors(kind: kind, activity: activity)
        wordsOnBlock
            .frame(
                maxWidth: .infinity, minHeight: layout == .strip ? CGFloat(Self.stripHeight) : nil,
                maxHeight: layout == .strip ? nil : .infinity, alignment: wordsAlignment
            )
            .background {
                Color(role: colors.fill, in: colors.scene)
                if let photo { photo.resizable().scaledToFill() }
            }
            .overlay(alignment: .topLeading) {
                if let day {
                    Text(verbatim: String(day))
                        .typeStyle(layout == .tile ? TypeRamp.scoreCaption : TypeRamp.scoreSmall)
                        .opacity(layout == .tile ? 1 : 0.75)
                        .padding(padding)
                }
            }
            .overlay(alignment: .topTrailing) {
                label
                    .typeStyle(layout == .tile ? TypeRamp.caption : TypeRamp.label)
                    .lineLimit(1)
                    .padding(padding)
            }
            .overlay(alignment: .bottomLeading) {
                if let minutes {
                    Text(verbatim: "\(minutes)′")
                        .typeStyle(layout == .tile ? TypeRamp.scoreSmall : TypeRamp.scoreCard)
                        .padding(.horizontal, padding)
                        .padding(.bottom, layout == .tile ? Space.xxs : Space.xs)
                        .accessibilityIdentifier("post.block.minutes")
                }
            }
            .foregroundStyle(Color(role: colors.ink, in: colors.scene))
            .clipped()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("post.block")
    }

    /// The words, all of them on a strip, which grows to hold them; a tile and a card keep their
    /// size and cut them short.
    @ViewBuilder private var wordsOnBlock: some View {
        if photo == nil, let words {
            Text(verbatim: words)
                .typeStyle(wordsStyle)
                .lineLimit(wordsLines)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: layout == .strip)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, padding)
                .padding(.top, layout == .tile ? 0 : Space.xl + Space.xxs)
                .padding(.bottom, minutes == nil ? padding : minutesHeight)
                .accessibilityIdentifier("post.block.words")
        } else {
            Color.clear
        }
    }

    /// A strip's least height, the design's: the words grow it from there.
    static let stripHeight: Double = 172

    /// The sport for a 练了, else the kind.
    private var label: Text {
        switch kind {
        case .trained: activity?.cardName ?? Text("练了", bundle: .module)
        case .healthyMeal: Text("健康餐", bundle: .module)
        case .cheatMeal: Text("放纵餐", bundle: .module)
        case .disclaimer: Text("请假条", bundle: .module)
        }
    }

    private var padding: Double { layout == .tile ? Space.xs : Space.m }

    /// Room kept under the words for the minutes.
    private var minutesHeight: Double { layout == .tile ? Space.l : Space.xxl }

    private var wordsAlignment: Alignment { layout == .tile ? .leading : .topLeading }

    private var wordsStyle: TypeStyle {
        switch layout {
        case .tile: TypeRamp.footnoteEmphasis
        case .strip: TypeRamp.title
        case .card: TypeRamp.action
        }
    }

    private var wordsLines: Int? {
        switch layout {
        case .tile: 3
        case .strip: nil
        case .card: 6
        }
    }
}

/// A post block's colours. Only the design system's: a 练了 takes the scene its sport's category
/// belongs to, a meal the scene of its kind, and a 请假条 the brand's graphite.
public struct PostBlockColors: Sendable {
    public let scene: SceneTheme
    public let fill: ColorRole
    public let ink: ColorRole

    public init(kind: CheckInKind, activity: Activity?) {
        switch kind {
        case .trained: self.init(scene: activity.map(Self.scene(of:)) ?? .gym)
        case .healthyMeal: self.init(scene: .tennis)
        case .cheatMeal: self.init(scene: .track)
        case .disclaimer: self.init(scene: .gym, fill: .bgBrand, ink: .fgOnBrand)
        }
    }

    /// A check-in's colours.
    public init(checkIn: CheckIn) {
        switch checkIn.entry {
        case .trained(let training): self.init(kind: .trained, activity: training.activity)
        case .healthyMeal: self.init(kind: .healthyMeal, activity: nil)
        case .cheatMeal: self.init(kind: .cheatMeal, activity: nil)
        case .disclaimer: self.init(kind: .disclaimer, activity: nil)
        }
    }

    private init(scene: SceneTheme, fill: ColorRole = .bgAccent, ink: ColorRole = .fgOnAccent) {
        self.scene = scene
        self.fill = fill
        self.ink = ink
    }

    /// Each category of the sports list on a scene: Tracy's pick (2026-10-31). A category added
    /// later, or a sport people name themselves, takes the gym's.
    static let sceneByCategory: [String: SceneTheme] = [
        "runWalk": .track, "cardio": .track, "cycling": .track, "combat": .track,
        "water": .pool,
        "strength": .gym, "everyday": .gym,
        "racket": .tennis, "ball": .tennis,
        "outdoorWinter": .climbing, "mindBody": .climbing, "dance": .climbing,
    ]

    static func scene(of activity: Activity) -> SceneTheme {
        guard case .sport(let sport) = activity, let category = sport.entry?.category else { return .gym }
        return sceneByCategory[category] ?? .gym
    }
}
#endif
