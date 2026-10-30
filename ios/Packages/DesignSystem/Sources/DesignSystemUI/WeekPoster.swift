#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Where a `WeekPoster`'s pieces sit, in poster points, from the two approved boards.
public struct WeekPosterLayout: Sendable, Equatable {
    /// The strip along the bottom.
    public static let stripHeight: Double = 44

    /// Nil: the width the poster is given.
    public let width: Double?
    public let height: Double
    public let titleStyle: TypeStyle
    /// The name and dates stop here (short of the 出赛表's title stickers); nil runs on.
    public let titleWidth: Double?
    public let weekNumberStyle: TypeStyle
    /// Puts the number's baseline where the board has it.
    public let weekNumberTop: Double
    /// Where the rows start, under the number, and how wide they run; nil is the poster's width.
    public let rowsTop: Double
    public let rowsLeading: Double
    public let rowsWidth: Double?
    public let characterSize: CGSize
    /// From the poster's bottom right corner to the character's.
    public let characterInset: CGSize

    /// The 出赛表's poster: 3:4 at 360 × 480, so the screen and the saved picture are one drawing.
    public static let poster = WeekPosterLayout(
        width: 360, height: 480, titleStyle: TypeRamp.footnoteEmphasis, titleWidth: 200,
        weekNumberStyle: TypeRamp.posterWeek, weekNumberTop: 12,
        rowsTop: 150, rowsLeading: 0, rowsWidth: nil,
        characterSize: CGSize(width: 132, height: 157),
        characterInset: CGSize(width: Space.xxs + 2, height: stripHeight - Space.xxs))

    /// Sign-up's 本周目标 card: the page's width and 460 tall, its number (112, italic, set
    /// tight) and character smaller, the rows on the left clear of the character.
    public static let card = WeekPosterLayout(
        width: nil, height: 460, titleStyle: TypeRamp.calloutEmphasis, titleWidth: nil,
        weekNumberStyle: TypeStyle(face: .scoreboard(.extraBoldItalic), size: 112, tracking: -4, anchor: .largeTitle),
        weekNumberTop: 15,
        rowsTop: 138, rowsLeading: Space.xs + 2, rowsWidth: 196,
        characterSize: CGSize(width: 92, height: 120),
        characterInset: CGSize(width: 30, height: 56))
}

/// The week as a poster, wherever a member plans or shares one (sign-up's 本周目标, the 出赛表):
/// who and which dates along the top, the week's number in big italic under them, a row a day,
/// the member's character in the bottom corner and a darker strip along the bottom. A picture
/// with a fixed layout, so its type doesn't grow with Dynamic Type.
///
/// The caller draws what changes between screens: the rows, the strip's content, the character,
/// anything behind the rows (`backdrop`, the scene's props) or over them (`overlay`, the title
/// stickers), and picks the card's `fill` and the `ink` on it (the brand's in sign-up, the
/// scene's on the 出赛表).
public struct WeekPoster<Backdrop: View, Rows: View, Character: View, Overlay: View, Strip: View>: View {
    @Environment(\.sceneTheme) private var theme

    private let title: String
    private let weekNumber: Int
    private let layout: WeekPosterLayout
    private let fill: ColorRole
    private let ink: ColorRole
    private let backdrop: Backdrop
    private let rows: Rows
    private let character: Character
    private let overlay: Overlay
    private let strip: Strip

    /// The strip: the fill, a shade darker.
    private let stripShade = 0.16

    /// `title` is the line along the top (Tracy · 10.20–10.26); `weekNumber` is shown as W43.
    public init(
        title: String, weekNumber: Int, layout: WeekPosterLayout, fill: ColorRole, ink: ColorRole,
        @ViewBuilder backdrop: () -> Backdrop, @ViewBuilder rows: () -> Rows,
        @ViewBuilder character: () -> Character, @ViewBuilder overlay: () -> Overlay,
        @ViewBuilder strip: () -> Strip
    ) {
        self.title = title
        self.weekNumber = weekNumber
        self.layout = layout
        self.fill = fill
        self.ink = ink
        self.backdrop = backdrop()
        self.rows = rows()
        self.character = character()
        self.overlay = overlay()
        self.strip = strip()
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color(role: fill, in: theme)
            backdrop
                .allowsHitTesting(false)
            Text(verbatim: title)
                .typeStyle(layout.titleStyle)
                .lineLimit(1)
                .frame(maxWidth: layout.titleWidth, alignment: .leading)
                .padding(.leading, Space.m + 2)
                .padding(.top, Space.s + 2)
            Text(verbatim: "W\(weekNumber)")
                .typeStyle(layout.weekNumberStyle)
                .fixedSize()
                .padding(.leading, Space.s + 2)
                .padding(.top, layout.weekNumberTop)
                .allowsHitTesting(false)
                .accessibilityLabel(Text("第 \(weekNumber) 周", bundle: .module))
            rows
                .frame(maxWidth: layout.rowsWidth ?? .infinity)
                .padding(.leading, layout.rowsLeading)
                .padding(.top, layout.rowsTop)
            character
                .frame(width: layout.characterSize.width, height: layout.characterSize.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, layout.characterInset.width)
                .padding(.bottom, layout.characterInset.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            overlay
            strip
                .frame(maxWidth: .infinity)
                .frame(height: WeekPosterLayout.stripHeight)
                .background(Color(role: .fgDefault, in: theme).opacity(stripShade))
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(minWidth: layout.width, maxWidth: layout.width ?? .infinity)
        .frame(height: layout.height)
        .foregroundStyle(Color(role: ink, in: theme))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        // A picture with a fixed layout: its type doesn't grow with Dynamic Type.
        .dynamicTypeSize(.large)
    }
}

extension WeekPoster where Backdrop == EmptyView, Overlay == EmptyView {
    /// A poster with nothing behind or over its rows.
    public init(
        title: String, weekNumber: Int, layout: WeekPosterLayout, fill: ColorRole, ink: ColorRole,
        @ViewBuilder rows: () -> Rows, @ViewBuilder character: () -> Character, @ViewBuilder strip: () -> Strip
    ) {
        self.init(
            title: title, weekNumber: weekNumber, layout: layout, fill: fill, ink: ink,
            backdrop: { EmptyView() }, rows: rows, character: character, overlay: { EmptyView() }, strip: strip)
    }
}
#endif
