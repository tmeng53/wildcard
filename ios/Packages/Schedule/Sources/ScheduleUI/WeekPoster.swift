#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import ScheduleDomain
import SwiftUI

/// The week as a 3:4 poster in the scene's color: who and which dates, the week's number, a
/// swim lane a day, the member's character cheering in the corner, the titles the weekly awards
/// gave them, and the week's 饮食小目标 and count along the bottom. Drawn at 360 × 480 points and
/// scaled to fit, so the saved picture and the screen are the same drawing.
struct WeekPoster: View {
    /// The poster's own size, in points; 3:4.
    static let size = CGSize(width: 360, height: 480)

    let content: PosterContent
    let player: CharacterPlayer?
    /// Saving: the character holds one pose, since a picture can't move.
    var isStill = false
    var onTapLane: (Int) -> Void = { _ in }
    var onTapTitle: (AwardTitle) -> Void = { _ in }
    var onTapFuel: () -> Void = {}

    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Positions from the approved design, in poster points.
    /// Where the lanes start, under the week's number.
    private let lanesTop: Double = 150
    private let laneHeight: Double = 40
    private let bottomBarHeight: Double = 44
    /// The character's frame, its right edge just inside the poster's.
    private let characterSize = CGSize(width: 132, height: 157)
    /// The week's number sits so its baseline lands 140 points down.
    private let weekNumberTop: Double = 12
    /// Lanes alternate with a faint shade; today's is darker.
    private let stripeShade = 0.06
    private let todayShade = 0.18
    private let barShade = 0.16
    /// Days off fade back, so the training days read first.
    private let restOpacity = 0.55
    private let restNumberOpacity = 0.4
    private let numberOpacity = 0.9
    /// The line over the first lane.
    private let lanesRule: Double = 2
    /// Each title sticker leans a little, like it was slapped on.
    private let stickerTilts: [Double] = [3, -2, 2]
    private let stickerHeight: Double = 28
    private let markSize: Double = 17
    private let leaveTagHeight: Double = 20
    private let numberWidth: Double = 20
    private let weekdayWidth: Double = 30
    /// A lifted rest day grows a touch, picked up off the poster.
    private let liftedScale = 1.02
    /// The name and dates stop short of the title stickers.
    private let titleWidth: Double = 200
    /// The award line drops over the lanes, under the stickers.
    private let awardLineTop: Double = 112
    /// A swap target's faint white fill.
    private let targetFill = 0.12

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
            awardLine
            bottomBar
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
    /// The faint dark shade over lanes and the bottom bar.
    private var shade: Color { Color(role: .fgDefault, in: theme) }

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
            Text(verbatim: ScheduleLabels.week(content.weekStart))
                .typeStyle(TypeRamp.posterWeek)
                .fixedSize()
                .padding(.leading, Space.s + 2)
                .padding(.top, weekNumberTop)
                .allowsHitTesting(false)
                .accessibilityLabel(Text("第 \(content.weekStart.weekOfYear) 周", bundle: .module))
        }
    }

    // MARK: Lanes

    private var lanes: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ink.opacity(numberOpacity))
                .frame(height: lanesRule)
            ForEach(content.lanes) { lane in
                laneButton(lane)
            }
        }
        .frame(width: Self.size.width)
    }

    private func laneButton(_ lane: PosterContent.Lane) -> some View {
        let isHeld = lane.look == .held
        let isRest = lane.plan == .rest
        let fore = isHeld ? Color(role: .fgAccent, in: theme) : ink
        return Button {
            onTapLane(lane.index)
        } label: {
            HStack(spacing: Space.s - 2) {
                Text(verbatim: "\(lane.index + 1)")
                    .typeStyle(TypeRamp.scoreInline)
                    .frame(width: numberWidth, alignment: .leading)
                    .opacity(isRest && !isHeld ? restNumberOpacity : numberOpacity)
                Group {
                    if lane.isToday {
                        Text("今天", bundle: .module)
                    } else {
                        ScheduleLabels.weekday(lane.day)
                    }
                }
                .typeStyle(TypeRamp.label)
                .frame(width: weekdayWidth, alignment: .leading)
                ScheduleLabels.plan(lane.plan)
                    .typeStyle(TypeRamp.headline)
                    .lineLimit(1)
                    .opacity(isRest && !isHeld ? restOpacity : 1)
                mark(lane, onWhite: isHeld)
                if lane.look == .swapTarget {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: Sizing.smallIcon, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(fore)
            .padding(.horizontal, Space.m)
            .frame(width: Self.size.width, height: laneHeight)
            .background { laneFill(lane) }
            .overlay(alignment: .bottom) {
                LaneRope(theme: theme)
                    .frame(height: 4)
                    .offset(y: 2)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(lane.isLifted ? liftedScale : 1)
        .zIndex(isHeld ? 1 : 0)
        .disabled(!lane.isEditable)
        .animation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion), value: lane.isLifted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(laneAccessibilityLabel(lane))
        .accessibilityAddTraits(isHeld ? .isSelected : [])
        .accessibilityIdentifier("schedule.lane.\(lane.index)")
    }

    @ViewBuilder
    private func laneFill(_ lane: PosterContent.Lane) -> some View {
        switch lane.look {
        case .held: ink
        case .swapTarget:
            ink.opacity(targetFill)
                .overlay { Rectangle().strokeBorder(ink, lineWidth: Sizing.selectionStroke) }
        case .today: shade.opacity(todayShade)
        case .plain: lane.index.isMultiple(of: 2) ? Color.clear : shade.opacity(stripeShade)
        }
    }

    /// A tick for a day trained, 请假 for a 请假条.
    @ViewBuilder
    private func mark(_ lane: PosterContent.Lane, onWhite: Bool) -> some View {
        let disc = onWhite ? Color(role: .bgAccentSubtle, in: theme) : ink
        let glyph = Color(role: .fgAccent, in: theme)
        switch lane.mark {
        case .trained:
            Image(systemName: "checkmark")
                .font(.system(size: markSize * 0.55, weight: .heavy))
                .foregroundStyle(glyph)
                .frame(width: markSize, height: markSize)
                .background(disc, in: Circle())
                .accessibilityHidden(true)
        case .disclaimer:
            Text("请假", bundle: .module)
                .typeStyle(TypeRamp.label)
                .foregroundStyle(glyph)
                .padding(.horizontal, Space.xs - 1)
                .frame(height: leaveTagHeight)
                .background(disc, in: Capsule())
        case .none:
            EmptyView()
        }
    }

    private func laneAccessibilityLabel(_ lane: PosterContent.Lane) -> Text {
        let day = lane.isToday ? Text("今天", bundle: .module) : ScheduleLabels.weekday(lane.day)
        let status: Text =
            switch lane.mark {
            case .trained: Text("，练了", bundle: .module)
            case .disclaimer: Text("，请假", bundle: .module)
            case .none: Text(verbatim: "")
            }
        return Text("\(day) \(ScheduleLabels.plan(lane.plan))\(status)", bundle: .module)
    }

    // MARK: Character, titles, award line

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
        .padding(.bottom, bottomBarHeight - Space.xxs)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var stickers: some View {
        VStack(alignment: .trailing, spacing: Space.xs - 2) {
            ForEach(Array(content.titles.enumerated()), id: \.element) { position, title in
                Button {
                    onTapTitle(title)
                } label: {
                    HStack(spacing: Space.xxs + 1) {
                        Image(systemName: "medal.fill")
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
                    .frame(minHeight: Sizing.minimumTapTarget - Space.s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("头衔：\(title.title)", bundle: .module))
                .accessibilityHint(Text("看颁奖词", bundle: .module))
                .accessibilityAddTraits(content.openTitle == title ? .isSelected : [])
                .accessibilityIdentifier("schedule.title.\(position)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, Space.s)
        .padding(.top, Space.xs)
    }

    @ViewBuilder
    private var awardLine: some View {
        if let title = content.openTitle {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("颁奖词 · \(title.title)", bundle: .module)
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgAccent, in: theme))
                Text(verbatim: title.speech)
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.m)
            .background(ink, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .padding(.horizontal, Space.s)
            .padding(.top, awardLineTop)
            .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("schedule.awardLine")
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: Space.xs) {
            fuelButton
            Spacer(minLength: 0)
            tally
        }
        .padding(.leading, Space.s - 2)
        .padding(.trailing, Space.s)
        .frame(width: Self.size.width, height: bottomBarHeight)
        .background(shade.opacity(barShade))
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var fuelButton: some View {
        let open = content.fuelOpen
        return Button(action: onTapFuel) {
            HStack(spacing: Space.xs - 2) {
                Image(systemName: "fork.knife")
                    .font(.system(size: Sizing.smallIcon - 2, weight: .semibold))
                    .accessibilityHidden(true)
                Group {
                    if content.fuel.isEmpty {
                        Text("饮食小目标", bundle: .module)
                    } else {
                        Text(verbatim: content.fuel.map(ScheduleLabels.fuelName).joined(separator: " · "))
                    }
                }
                .typeStyle(TypeRamp.footnoteEmphasis)
                .lineLimit(1)
            }
            .foregroundStyle(open ? Color(role: .fgAccent, in: theme) : ink)
            .padding(.horizontal, Space.s)
            .frame(height: Sizing.compactControl - Space.xxs)
            .background(open ? ink : Color.clear, in: Capsule())
            .frame(minHeight: bottomBarHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!content.fuelEditable)
        .accessibilityAddTraits(open ? .isSelected : [])
        .accessibilityIdentifier("schedule.fuel")
    }

    private var tally: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs - 2) {
            switch content.tally {
            case .trained(let trained, let planned, let isPast):
                Group {
                    if isPast { Text("练了", bundle: .module) } else { Text("本周", bundle: .module) }
                }
                .typeStyle(TypeRamp.label)
                Text(verbatim: "\(trained)/\(planned)")
                    .typeStyle(TypeRamp.scoreInline)
                    .contentTransition(.numericText(value: Double(trained)))
            case .planned(let train, let rest):
                Text("\(train) 练 \(rest) 休", bundle: .module)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .contentTransition(.numericText(value: Double(train)))
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule.tally")
    }
}

/// The dotted lane rope along the bottom of each lane: pool floats, or a fine dotted line on
/// the other scenes.
private struct LaneRope: View {
    let theme: SceneTheme

    var body: some View {
        Canvas { context, size in
            let isPool = theme == .pool
            let gap = isPool ? 9.0 : 4.0
            let radius = isPool ? 2.2 : 0.9
            let color = Color(role: .bgCanvas, in: theme).opacity(isPool ? 0.75 : 0.6)
            var x = 4.0
            while x < size.width {
                let dot = CGRect(x: x - radius, y: size.height / 2 - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: dot), with: .color(color))
                x += gap
            }
        }
    }
}
#endif
