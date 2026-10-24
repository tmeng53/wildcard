#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import ScheduleDomain
import SwiftUI

/// The week as a 3:4 poster in the scene's color: who and which dates, the week's number, a
/// swim lane a day, the member's character cheering in the corner, the titles the weekly awards
/// gave them as stickers (their 颁奖词 sit under the poster), and the week's 饮食小目标 and
/// count along the bottom. Drawn at 360 × 480 points and scaled to fit, so the saved picture
/// and the screen are the same drawing.
struct WeekPoster: View {
    /// The poster's own size, in points; 3:4.
    static let size = CGSize(width: 360, height: 480)

    let content: PosterContent
    let player: CharacterPlayer?
    /// Saving: the character holds one pose, since a picture can't move.
    var isStill = false
    var onTapLane: (Int) -> Void = { _ in }
    var onTapFuel: () -> Void = {}

    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Positions from the approved design, in poster points.
    /// Where the lanes start, under the week's number.
    private let lanesTop: Double = 150
    /// The character's frame, its right edge just inside the poster's.
    private let characterSize = CGSize(width: 132, height: 157)
    /// The week's number sits so its baseline lands 140 points down.
    private let weekNumberTop: Double = 12
    private let numberOpacity = 0.9
    /// The line over the first lane.
    private let lanesRule: Double = 2
    /// Each title sticker leans a little, like it was slapped on.
    private let stickerTilts: [Double] = [3, -2, 2]
    private let stickerHeight: Double = 28
    /// The name and dates stop short of the title stickers.
    private let titleWidth: Double = 200

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(role: .bgAccent, in: theme)
            PosterArt(theme: theme)
                .allowsHitTesting(false)
            header
            lanes
                .offset(y: lanesTop)
            character
            stickers
            PosterBottomBar(content: content, theme: theme, onTapFuel: onTapFuel)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(ink)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        // The poster is a picture with a fixed layout: its type doesn't grow with Dynamic Type.
        .dynamicTypeSize(.large)
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: content)
    }

    /// White on the scene's color: the poster's ink, in every scene.
    private var ink: Color { Color(role: .bgCanvas, in: theme) }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .topLeading) {
            Text(verbatim: "\(content.nickname) · \(ScheduleLabels.dates(content.weekStart, content.weekEnd))")
                .typeStyle(TypeRamp.footnoteEmphasis)
                .lineLimit(1)
                .frame(maxWidth: titleWidth, alignment: .leading)
                .padding(.leading, Space.m + 2)
                .padding(.top, Space.s + 2)
                .accessibilityIdentifier("schedule.poster.title")
            Text(verbatim: ScheduleLabels.week(content.weekNumber))
                .typeStyle(TypeRamp.posterWeek)
                .fixedSize()
                .padding(.leading, Space.s + 2)
                .padding(.top, weekNumberTop)
                .allowsHitTesting(false)
                .accessibilityLabel(Text("第 \(content.weekNumber) 周", bundle: .module))
        }
    }

    // MARK: Lanes

    private var lanes: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ink.opacity(numberOpacity))
                .frame(height: lanesRule)
            ForEach(content.lanes) { lane in
                PosterLane(lane: lane, theme: theme, onTap: onTapLane)
            }
        }
        .frame(width: Self.size.width)
    }

    // MARK: Character, titles

    private var character: some View {
        Group {
            if let player {
                if isStill {
                    let frame = player.frame(at: .now)
                    CharacterCanvas(drawing: frame.drawing, placements: frame.placements)
                        .aspectRatio(player.drawing.width / player.drawing.height, contentMode: .fit)
                } else {
                    CharacterView(player: player)
                }
            }
        }
        .frame(width: characterSize.width, height: characterSize.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, Space.xxs + 2)
        .padding(.bottom, PosterBottomBar.height - Space.xxs)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var stickers: some View {
        VStack(alignment: .trailing, spacing: Space.xs - 2) {
            ForEach(Array(content.titles.enumerated()), id: \.element) { position, title in
                HStack(spacing: Space.xxs + 1) {
                    Image(systemName: "star.fill")
                        .font(.system(size: Sizing.smallIcon - 2, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(verbatim: title.title)
                        .typeStyle(TypeRamp.footnoteEmphasis)
                        .lineLimit(1)
                }
                .foregroundStyle(Color(role: .fgAccent, in: theme))
                .padding(.leading, Space.xs + 1)
                .padding(.trailing, Space.s)
                .frame(height: stickerHeight)
                .background(ink, in: Capsule())
                .rotationEffect(.degrees(stickerTilts[position % stickerTilts.count]))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("头衔：\(title.title)", bundle: .module))
                .accessibilityIdentifier("schedule.title.\(position)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, Space.s)
        .padding(.top, Space.s)
        .allowsHitTesting(false)
    }
}
#endif
