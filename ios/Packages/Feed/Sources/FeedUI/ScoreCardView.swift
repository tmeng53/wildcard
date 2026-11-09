#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SportsUI
import SwiftUI

/// The 成绩卡 (Tracy, 2026-11-09), drawn at 360 × 480 points, so the preview and the saved picture
/// are one drawing. Over a picture (A2): the post's photo, route or chart on top, and under it a
/// band in the sport category's colour with the poster's faint grid, the big number with its unit
/// and the sport, the 成绩条's other numbers on a darker band, 本周第 N 次 and the squad's name,
/// and the character standing on the seam at the right. Without one (A, 纯色): the whole card in
/// the colour, the number poster-sized, the sport and the caption under it, the character cheering
/// at the right. The member's name and the day top left, the logo in its own colours top right.
///
/// On the preview, a tap on the number takes the next one, a tap on a number of the strip strikes
/// it (faded and crossed through) and a tap on the character hops it into its next pose. Saved,
/// the struck numbers are left out and nothing moves.
struct ScoreCardView: View {
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: ScoreCardModel
    /// Drawn for the saved picture: no taps, no struck numbers.
    var isSaving = false

    private var card: ScoreCard { model.card }
    private var colors: PostBlockColors { PostBlockColors(kind: .trained, activity: model.training.activity) }
    private var ink: Color { Color(colors.ink) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(colors.fill)
            if card.isPlain { plain } else { overPicture }
        }
        .frame(width: ScoreCardModel.size.width, height: ScoreCardModel.size.height)
        .clipped()
        .foregroundStyle(ink)
        // A picture with a fixed layout: its type doesn't grow with Dynamic Type.
        .dynamicTypeSize(.large)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scoreCard")
    }

    // MARK: A2, over a picture

    private var overPicture: some View {
        ZStack(alignment: .topLeading) {
            PosterGrid(color: ink)
                .padding(.top, CardLayout.pictureHeight)
            backdrop
                .frame(width: ScoreCardModel.pictureSize.width, height: ScoreCardModel.pictureSize.height)
                .clipped()
            LinearGradient(
                colors: [Color(role: .fgDefault, in: .gym).opacity(CardLayout.shade), .clear], startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: CardLayout.shadeHeight)
            .accessibilityHidden(true)
            topLine
            heroLine
                .padding(.leading, CardLayout.heroLeading)
                .padding(.top, CardLayout.pictureHeight + CardLayout.bandHeroTop)
            strip(trailingRoom: CardLayout.bandStripRoom)
                .padding(.top, CardLayout.pictureHeight + CardLayout.bandStripTop)
            footLine
            character(
                left: CardLayout.seamCharacterLeft, top: CardLayout.seamCharacterTop,
                width: CardLayout.seamCharacterWidth)
        }
    }

    @ViewBuilder private var backdrop: some View {
        switch card.backdrop {
        case .photo(let ref):
            if let photo = model.photos[ref] {
                Image(decorative: photo, scale: 1).resizable().scaledToFill()
            } else {
                Color(colors.shade)
            }
        case .map:
            if let map = model.map {
                Image(uiImage: map).resizable().scaledToFill()
            } else {
                Color(colors.shade)
            }
        case .chart:
            if let series = model.training.workout?.series {
                WorkoutChart(series: series, activity: model.training.activity)
            }
        case .plain:
            EmptyView()
        }
    }

    /// 7.4 公里 跑步, on the band.
    private var heroLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: CardLayout.unitGap) {
            if let hero = card.hero, let cell = model.cells[hero] {
                heroButton {
                    HStack(alignment: .firstTextBaseline, spacing: CardLayout.unitGap) {
                        Text(verbatim: cell.value)
                            .typeStyle(TypeRamp.scoreCardHero)
                            .minimumScaleFactor(CardLayout.numberShrink)
                        (cell.unit?.text ?? cell.label.text).typeStyle(TypeRamp.headline)
                    }
                }
                model.training.activity.name
                    .typeStyle(TypeRamp.headline)
                    .opacity(CardLayout.sportOpacity)
                    .padding(.leading, Space.xs)
            } else {
                model.training.activity.name.typeStyle(TypeRamp.title)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: ScoreCardModel.size.width - 2 * CardLayout.heroLeading, alignment: .leading)
    }

    // MARK: A, 纯色

    private var plain: some View {
        ZStack(alignment: .topLeading) {
            PosterGrid(color: ink)
            topLine
            if let hero = card.hero, let cell = model.cells[hero] {
                heroButton {
                    HStack(alignment: .firstTextBaseline, spacing: CardLayout.unitGap) {
                        Text(verbatim: cell.value)
                            .typeStyle(TypeRamp.posterWeek)
                            .minimumScaleFactor(CardLayout.numberShrink)
                        (cell.unit?.text ?? cell.label.text).typeStyle(TypeRamp.title)
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: ScoreCardModel.size.width - 2 * CardLayout.heroLeading, alignment: .leading)
                .padding(.leading, CardLayout.heroLeading)
                .padding(.top, CardLayout.posterHeroTop)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                model.training.activity.name.typeStyle(TypeRamp.title).lineLimit(1)
                if let caption = model.training.caption?.text {
                    Text(verbatim: caption)
                        .typeStyle(TypeRamp.callout)
                        .opacity(CardLayout.sportOpacity)
                        .lineLimit(CardLayout.captionLines)
                        .frame(width: CardLayout.captionWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, CardLayout.margin)
            .padding(.top, CardLayout.posterSportTop)
            character(
                left: CardLayout.posterCharacterLeft, top: CardLayout.posterCharacterTop,
                width: CardLayout.posterCharacterWidth)
            strip(trailingRoom: 0)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, CardLayout.posterStripBottom)
            footLine
        }
    }

    // MARK: Shared pieces

    /// Tracy · 11.9 周日 and the logo.
    private var topLine: some View {
        HStack {
            Text(verbatim: dayLine)
                .typeStyle(TypeRamp.footnoteEmphasis)
                .lineLimit(1)
            Spacer(minLength: Space.s)
            TicketLogo(on: .bgBrandPage, ink: .bgBrand)
                .frame(width: CardLayout.logo, height: CardLayout.logo)
        }
        .padding(.horizontal, CardLayout.margin)
        .padding(.top, CardLayout.topLineTop)
    }

    /// The member's name and the day the post counts for: Tracy · 11.9 周日.
    private var dayLine: String {
        let day = model.checkIn.day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = CardLayout.utc
        let noon = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
        let weekday = noon?.formatted(Date.FormatStyle(timeZone: CardLayout.utc).weekday(.abbreviated).locale(locale))
        let date = ["\(day.month).\(day.day)", weekday].compactMap { $0 }.joined(separator: " ")
        return [model.nickname, date].compactMap { $0 }.joined(separator: " · ")
    }

    /// The strip's numbers on a darker band; on the preview a tap strikes one, saved the struck
    /// are left out. Nothing when there are none.
    @ViewBuilder private func strip(trailingRoom: Double) -> some View {
        let shown = (isSaving ? card.savedStrip : card.strip).compactMap { model.cells[$0] }
        if !shown.isEmpty {
            Group {
                if isSaving {
                    ScoreStrip(cells: shown, activity: model.training.activity, fill: .none)
                } else {
                    ScoreStrip(
                        cells: shown, activity: model.training.activity, struck: card.struck, fill: .none,
                        onToggle: model.tap)
                }
            }
            .padding(.trailing, trailingRoom)
            .background(Color(colors.shade))
            .accessibilityIdentifier("scoreCard.strip")
        }
    }

    /// 本周第 3 次 bottom left, the squad's name bottom right.
    private var footLine: some View {
        HStack(spacing: Space.s) {
            if let count = model.weekCount {
                Text(copy: "本周第 \(count) 次", bundle: .module)
                    .layoutPriority(1)
                    .accessibilityIdentifier("scoreCard.weekCount")
            }
            Spacer(minLength: 0)
            if card.showsSquad, let squad = model.squadName {
                Text(verbatim: squad)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("scoreCard.squad")
            }
        }
        .typeStyle(TypeRamp.label)
        .lineLimit(1)
        .padding(.horizontal, CardLayout.margin)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, CardLayout.footBottom)
    }

    /// The big number: on the preview, a tap takes the next one.
    @ViewBuilder private func heroButton(@ViewBuilder label: () -> some View) -> some View {
        if isSaving {
            label()
        } else {
            Button(action: model.tapHero, label: label)
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint(Text(copy: "点一下换一个数字", bundle: .module))
                .accessibilityIdentifier("scoreCard.hero")
        }
    }

    /// The character's whole rig, `width` points wide with its 4:3 canvas, its canvas's top left
    /// corner at (`left`, `top`) in card points. Drawn with room either side, so a pose that
    /// swings past the canvas shows whole. On the preview a tap hops it into its next pose.
    @ViewBuilder private func character(left: Double, top: Double, width: Double) -> some View {
        if let still = model.still {
            let room = width * CardLayout.room.width / CardLayout.rig.width
            let figure = CharacterCanvas(drawing: still.drawing, placements: still.placements, crop: CardLayout.room)
                .frame(width: room, height: width * CardLayout.room.height / CardLayout.rig.width)
            Group {
                if isSaving {
                    figure
                } else {
                    Button(action: model.tapCharacter) { figure }
                        .buttonStyle(.plain)
                        .keyframeAnimator(initialValue: 0.0, trigger: model.hops) { content, lift in
                            content.offset(y: reduceMotion ? 0 : lift)
                        } keyframes: { _ in
                            KeyframeTrack {
                                CubicKeyframe(-CardLayout.hop, duration: 0.14)
                                SpringKeyframe(0, duration: 0.24, spring: .bouncy)
                            }
                        }
                        .accessibilityLabel(Text(copy: "人物", bundle: .module))
                        .accessibilityHint(Text(copy: "点一下换个姿势", bundle: .module))
                        .accessibilityIdentifier("scoreCard.character")
                }
            }
            .offset(x: left - (room - width) / 2, y: top)
        }
    }
}

/// Where the pieces sit, from the approved design, in card points.
private enum CardLayout {
    static let margin: Double = 20
    static let topLineTop: Double = 18
    static let logo: Double = 32
    static let footBottom: Double = 12
    static let heroLeading: Double = 16
    /// Between the big number and its unit.
    static let unitGap: Double = 6
    static let sportOpacity = 0.9
    /// A long number (1,860 米) shrinks to fit rather than run off the card.
    static let numberShrink = 0.5
    static let utc = TimeZone(identifier: "UTC") ?? .gmt

    // A2
    static let pictureHeight: Double = 300
    static let shadeHeight: Double = 70
    static let shade = 0.28
    static let bandHeroTop: Double = 10
    static let bandStripTop: Double = 80
    /// The strip's numbers stop short of the character on the seam.
    static let bandStripRoom: Double = 120
    static let seamCharacterLeft: Double = 234
    static let seamCharacterTop: Double = 212
    static let seamCharacterWidth: Double = 130

    // A
    static let posterHeroTop: Double = 44
    static let posterSportTop: Double = 182
    static let captionWidth: Double = 170
    static let captionLines = 5
    static let posterCharacterLeft: Double = 171
    static let posterCharacterTop: Double = 150
    static let posterCharacterWidth: Double = 195
    static let posterStripBottom: Double = 40

    /// The rig's canvas, and the part of it drawn: all of it, with 40 points more either side.
    static let rig = CGSize(width: 240, height: 320)
    static let room = CGRect(x: -40, y: 0, width: 320, height: 320)
    /// How high the character hops on a tap.
    static let hop: Double = 14
}

/// The poster's faint grid, a line every 30 points, over the card's colour.
private struct PosterGrid: View {
    let color: Color
    private static let step: Double = 30
    private static let opacity = 0.07

    var body: some View {
        Canvas { context, size in
            var lines = Path()
            for column in stride(from: Self.step, to: size.width, by: Self.step) {
                lines.addRect(CGRect(x: column, y: 0, width: Sizing.hairline, height: size.height))
            }
            for row in stride(from: Self.step, to: size.height, by: Self.step) {
                lines.addRect(CGRect(x: 0, y: row, width: size.width, height: Sizing.hairline))
            }
            context.fill(lines, with: .color(color.opacity(Self.opacity)))
        }
        .accessibilityHidden(true)
    }
}
#endif
