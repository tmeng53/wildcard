#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// A post's face where it has no photo, and the same corners over a photo where it has one: a
/// block in its sport's scene colour with the post's words on it, the sport or kind top right,
/// a 训练's minutes bottom left (not on a 动态 card, whose 成绩条 has them) and, on a tile, its
/// day top left. Every screen that shows a post
/// without a photo draws this one block: 我的动态's tiles, 动态's cards and the 战报's
/// 你最火的一条 (Tracy, 2026-11-02).
public struct PostBlock: View {
    /// Where the block sits, which sets its type and padding; the caller gives the frame.
    public enum Layout: Sendable {
        /// A square on 我的动态's wall.
        case tile
        /// A wide strip in place of a 动态 card's cover, its words at its foot; the 成绩条 under it
        /// has a 训练's minutes.
        case strip
        /// The 战报's tall card.
        case card
        /// A small square in a glimpse of the posts (我's 我的动态 tile): the colour or the photo,
        /// with a 练了's minutes only.
        case thumbnail
    }

    private let kind: CheckInKind
    private let activity: Activity?
    private let words: String?
    private let minutes: Int?
    private let day: Int?
    private let photo: Image?
    private let layout: Layout
    /// A 请假条 posted as 休息, a rest the member planned.
    private var restDay = false

    /// `activity` is a 练了's sport; `day` (the day of the month) shows top left where given;
    /// with a `photo` the block is that photo and leaves its words to the caller.
    public init(
        kind: CheckInKind, activity: Activity? = nil, words: String? = nil, minutes: Int? = nil, day: Int? = nil,
        photo: Image? = nil, layout: Layout
    ) {
        self.kind = kind
        self.activity = activity
        self.words = words
        self.minutes = layout == .strip ? nil : minutes
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
            restDay = disclaimer.restDay
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
                if let photo {
                    photo.resizable().scaledToFill()
                } else if layout == .strip, let activity {
                    SportPattern(symbol: activity.symbol, color: Color(role: .fgAccent, in: colors.scene))
                }
            }
            .overlay(alignment: .topLeading) {
                if let day, layout != .thumbnail {
                    Text(verbatim: String(day))
                        .typeStyle(layout == .tile ? TypeRamp.scoreCaption : TypeRamp.scoreSmall)
                        .opacity(layout == .tile ? 1 : 0.75)
                        .padding(padding)
                }
            }
            .overlay(alignment: .topTrailing) {
                if layout != .thumbnail {
                    label
                        .typeStyle(layout == .tile ? TypeRamp.caption : TypeRamp.label)
                        .lineLimit(1)
                        .padding(padding)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let minutes {
                    Text(verbatim: "\(minutes)′")
                        .typeStyle(minutesStyle)
                        .padding(.horizontal, padding)
                        .padding(.bottom, layout == .card || layout == .strip ? Space.xs : Space.xxs)
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
        if photo == nil, layout != .thumbnail, let words {
            Text(verbatim: words)
                .typeStyle(wordsStyle)
                .lineLimit(wordsLines)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: layout == .strip)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, padding)
                .padding(.top, wordsTop)
                .padding(.bottom, minutes == nil ? padding : minutesHeight)
                .accessibilityIdentifier("post.block.words")
        } else {
            Color.clear
        }
    }

    /// A strip's least height, the design's (Tracy, 2026-11-08): short when there are no words,
    /// which grow it from there.
    static let stripHeight: Double = 96

    /// The sport for a 练了, else the kind.
    private var label: Text {
        switch kind {
        case .trained: activity?.cardName ?? Text("训练", bundle: .module)
        case .healthyMeal: Text("健康餐", bundle: .module)
        case .cheatMeal: Text("放纵餐", bundle: .module)
        case .disclaimer:
            if restDay { Text("休息", bundle: .module) } else { Text("请假条", bundle: .module) }
        }
    }

    /// Room above the words for the label, and on a card for the day's bigger number too.
    private var wordsTop: Double {
        switch layout {
        case .tile, .thumbnail: 0
        case .strip: Space.xl + Space.xxs
        case .card: Space.xxl + Space.xs
        }
    }

    private var padding: Double {
        switch layout {
        case .tile: Space.xs
        case .thumbnail: Space.xxs
        case .strip, .card: Space.m
        }
    }

    private var minutesStyle: TypeStyle {
        switch layout {
        case .tile: TypeRamp.scoreSmall
        case .thumbnail: TypeRamp.scoreCaption
        case .strip, .card: TypeRamp.scoreCard
        }
    }

    /// Room kept under the words for the minutes.
    private var minutesHeight: Double { layout == .tile || layout == .thumbnail ? Space.l : Space.xxl }

    private var wordsAlignment: Alignment {
        switch layout {
        case .tile, .thumbnail: .leading
        case .strip: .bottomLeading
        case .card: .topLeading
        }
    }

    private var wordsStyle: TypeStyle {
        switch layout {
        case .tile, .thumbnail: TypeRamp.footnoteEmphasis
        case .strip: TypeRamp.title
        case .card: TypeRamp.action
        }
    }

    private var wordsLines: Int? {
        switch layout {
        case .tile, .thumbnail: 3
        case .strip: nil
        case .card: 6
        }
    }
}

/// A 练了's sport icon, upright, in rows that run diagonally and stagger, filling a strip without
/// a photo in a shade a step darker than the block (Tracy, 2026-11-08).
private struct SportPattern: View {
    let symbol: String
    let color: Color

    private static let icon: Double = 34
    private static let step: Double = 62
    private static let rowStep = step * 0.78
    private static let angle = -25.0 * Double.pi / 180

    var body: some View {
        Canvas { context, size in
            var glyph = context.resolve(Image(systemName: symbol))
            glyph.shading = .color(color)
            let natural = glyph.size
            guard natural.width > 0, natural.height > 0 else { return }
            let scale = Self.icon / max(natural.width, natural.height)
            let drawn = CGSize(width: natural.width * scale, height: natural.height * scale)
            let reach = Int((hypot(size.width, size.height) / Self.rowStep).rounded(.up)) / 2 + 1
            let (cosine, sine) = (cos(Self.angle), sin(Self.angle))
            for row in -reach...reach {
                for column in -reach...reach {
                    let along = Double(column) * Self.step + (row.isMultiple(of: 2) ? 0 : Self.step / 2)
                    let across = Double(row) * Self.rowStep
                    let center = CGPoint(
                        x: size.width / 2 + along * cosine - across * sine,
                        y: size.height / 2 + along * sine + across * cosine)
                    context.draw(
                        glyph,
                        in: CGRect(
                            x: center.x - drawn.width / 2, y: center.y - drawn.height / 2,
                            width: drawn.width, height: drawn.height))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A post block's colours: its scene's accent, with the words on it in the accent's ink. A 练了
/// takes the scene its sport's category belongs to, a meal the scene of its kind, and a 请假条 the
/// gym's. Never the brand's graphite: a run of 请假条 made 我的动态 a wall of black squares
/// (Tracy, 2026-11-08).
public struct PostBlockColors: Sendable {
    public let scene: SceneTheme
    public let fill = ColorRole.bgAccent
    public let ink = ColorRole.fgOnAccent

    public init(kind: CheckInKind, activity: Activity?) {
        switch kind {
        case .trained: self.init(scene: activity.map(Self.scene(of:)) ?? .gym)
        case .healthyMeal: self.init(scene: .tennis)
        case .cheatMeal: self.init(scene: .track)
        case .disclaimer: self.init(scene: .gym)
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

    private init(scene: SceneTheme) {
        self.scene = scene
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
