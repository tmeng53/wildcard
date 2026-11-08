#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// A post's face where it has no photo, and the same corners over a photo where it has one: a
/// block in its sport category's colour with the post's words on it, the sport or kind top right,
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
                Color(colors.fill)
                if let photo { photo.resizable().scaledToFill() }
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
            .foregroundStyle(Color(colors.ink))
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

    /// A strip's least height, the design's: the words grow it from there.
    static let stripHeight: Double = 150

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
#endif
