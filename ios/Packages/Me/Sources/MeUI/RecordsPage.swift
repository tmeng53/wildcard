#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import MeDomain
import SportsUI
import SwiftUI
import UIKit

/// 外卡记录, pushed over 我 from 训练记录's 全部数据: the member's records since they joined on
/// graphite tiles. 训练时间 leads, the member's character training at their top sport beside a
/// 24-hour clock of when they post, over their weekdays; then the streaks as logo tickets, 最常练,
/// the totals, and 和小队 (the best partner bumping fists with them, the cheers both ways). On
/// opening the numbers count up, the clock's hands grow, the bars rise and the tickets punch in,
/// a light tick each. 存图 saves the page as one picture. Before the first 练了 only the two
/// streak tiles show, at 0.
struct RecordsPage: View {
    let model: RecordsModel
    /// The member's own character, who trains on the page.
    let character: MeCharacter?
    @Environment(\.sceneTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picture: SavedRecords?
    @State private var cast = RecordsCast()

    var body: some View {
        Group {
            switch model.load {
            case .loading:
                Color.clear
            case .failed:
                MeFailed { Task { await model.reload() } }
            case .loaded(let records):
                ScrollView {
                    RecordsContent(records: records, cast: cast, today: today, playsIntro: true)
                }
                .scrollIndicators(.hidden)
                .barTitleOnScroll(Text("外卡记录", bundle: .module))
                .task(id: records) {
                    cast.dress(character, records: records)
                    guard !reduceMotion else { return }
                    await cast.bumpFists()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        saveButton(records)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        }
        .loadingCover(model.load == .loading) { MeLoading() }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .task { await model.reload() }
        .haptic(.appear, trigger: picture?.id)
        .sheet(item: $picture) { picture in
            SavePictureSheet(image: picture.image) { self.picture = nil }
                .environment(\.sceneTheme, theme)
        }
        .accessibilityIdentifier("records.page")
    }

    /// Today on this phone, for a streak that runs to it (10.6 – 今天).
    private var today: LocalDay { LocalDay(at: .now, in: .current) }

    private func saveButton(_ records: WildcardRecords) -> some View {
        Button {
            picture = SavedRecords(image: render(records))
        } label: {
            Label {
                Text("存图", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: Sizing.smallIcon + 2, weight: .medium))
            }
        }
        // The navigation bar shows a label's icon alone unless told otherwise.
        .labelStyle(.titleAndIcon)
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("records.save")
    }

    /// The page as one picture, as it stands once the opening has played, on white.
    private func render(_ records: WildcardRecords) -> UIImage {
        let renderer = ImageRenderer(
            content: RecordsContent(records: records, cast: cast, today: today, playsIntro: false)
                .frame(width: Self.pictureWidth)
                .background(Color(role: .bgCanvas, in: theme))
                .environment(\.sceneTheme, theme)
                .environment(\.locale, locale))
        renderer.scale = Self.pictureScale
        renderer.isOpaque = true
        return renderer.uiImage ?? UIImage()
    }

    /// The picture is the page at an iPhone's width, three pixels a point.
    private static let pictureWidth = 393.0
    private static let pictureScale = 3.0
}

/// 存图's picture, for its sheet.
private struct SavedRecords: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// The page's title and tiles. `playsIntro` plays the opening; a picture is drawn as it ends,
/// its characters standing still.
struct RecordsContent: View {
    let records: WildcardRecords
    let cast: RecordsCast
    let today: LocalDay
    let playsIntro: Bool
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var introDone = false
    /// Counts tickets punched in, for each one's tick.
    @State private var punched = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("外卡记录", bundle: .module)
                .typeStyle(TypeRamp.largeTitle)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .padding(.top, Space.xxs)
                .padding(.bottom, Self.titleGap)
                .accessibilityAddTraits(.isHeader)
            TimelineView(.animation(paused: !animates || introDone)) { timeline in
                tiles(at: animates ? timeline.date.timeIntervalSince(start) : RecordsIntro.end)
            }
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.bottom, Self.bottomGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .haptic(.tick, trigger: punched)
        .task {
            guard animates else { return }
            start = .now
            await punchTickets()
            try? await Task.sleep(for: .seconds(RecordsIntro.end))
            introDone = true
        }
    }

    private var animates: Bool { playsIntro && !reduceMotion }

    @ViewBuilder private func tiles(at time: Double) -> some View {
        let intro = RecordsIntro(time: time)
        VStack(spacing: Space.cardGap) {
            if records.hasTrained {
                RecordsHero(records: records, runner: cast.runner, still: !animates, intro: intro)
            }
            HStack(alignment: .top, spacing: Space.cardGap) {
                StreakTile(
                    label: Text("最长连续训练", bundle: .module), streak: records.longestStreak, today: today,
                    order: 0, intro: intro)
                StreakTile(
                    label: Text("健康餐连续", bundle: .module), streak: records.mealStreak, today: today,
                    order: 1, intro: intro)
            }
            .fixedSize(horizontal: false, vertical: true)
            if records.hasTrained {
                TopSportsTile(records: records, intro: intro)
                TotalsTile(records: records, intro: intro)
                if let squad = records.squad {
                    SquadRecordsSection(squad: squad, cast: cast, still: !animates, intro: intro)
                }
            }
        }
    }

    /// Ticks once as each ticket lands, as the tiles punch them in.
    private func punchTickets() async {
        let counts = [records.longestStreak?.days ?? 0, records.mealStreak?.days ?? 0].map(StreakTile.ticketsShown)
        let times =
            counts.enumerated()
            .flatMap { tile, count in (0..<count).map { RecordsIntro.ticketLands(tile: tile, index: $0) } }
            .sorted()
        var elapsed = 0.0
        for time in times {
            guard (try? await Task.sleep(for: .seconds(time - elapsed))) != nil else { return }
            elapsed = time
            punched += 1
        }
    }

    private static let titleGap = 20.0
    private static let bottomGap = 28.0
}

/// When each part of the opening plays, in seconds from the page opening, and how far along it
/// is: the numbers count up, the clock's hands grow round from midnight, the bars rise and the
/// tickets punch in, each a little after the one before.
struct RecordsIntro {
    let time: Double

    /// Everything has landed by now.
    static let end = 2.2

    /// How far a number is to its value, the `index`-th on the page.
    func number(_ index: Int) -> Double { Self.easeOut((time - 0.15 - Double(index) * 0.04) / 0.8) }

    /// How long the clock's hand for `hour` is, as a share of its length; it overshoots a little.
    func hand(_ hour: Int) -> Double { max(0, Self.back((time - 0.2 - Double(hour) * 0.035) / 0.5)) }

    /// How tall the `index`-th bar is, as a share of its height.
    func bar(_ index: Int) -> Double { Self.easeOut((time - 0.3 - Double(index) * 0.03) / 0.6) }

    /// How big a streak tile's `index`-th ticket is; it overshoots as it lands.
    func ticket(tile: Int, index: Int) -> Double {
        max(0, Self.back((time - Self.ticketStart(tile: tile, index: index)) / Self.ticketPunch))
    }

    static func ticketLands(tile: Int, index: Int) -> Double { ticketStart(tile: tile, index: index) + ticketPunch }

    private static func ticketStart(tile: Int, index: Int) -> Double {
        0.5 + Double(tile * StreakTile.mostTickets + index) * 0.09
    }

    private static let ticketPunch = 0.32

    private static func easeOut(_ fraction: Double) -> Double {
        1 - pow(1 - min(1, max(0, fraction)), 3)
    }

    /// Ease out with a little overshoot.
    private static func back(_ fraction: Double) -> Double {
        let clamped = min(1, max(0, fraction))
        let overshoot = 1.7
        return 1 + (overshoot + 1) * pow(clamped - 1, 3) + overshoot * pow(clamped - 1, 2)
    }
}

/// The characters on the page: the member training at their top sport, and the member and their
/// best partner bumping fists every few seconds.
@MainActor @Observable
final class RecordsCast {
    private(set) var runner: CharacterPlayer?
    private(set) var member: CharacterPlayer?
    private(set) var partner: CharacterPlayer?
    /// The heads by 收到加油 and 送出加油.
    private(set) var heads: [MemberID: CharacterPlayer] = [:]
    @ObservationIgnored private var personas: (member: Persona, partner: Persona) = (.energetic, .energetic)

    /// The member in their top sport's kit, the partner in their own clothes.
    func dress(_ character: MeCharacter?, records: WildcardRecords) {
        let look = character?.outfit ?? PlaceholderCharacter.lifter
        let persona = character?.persona ?? .energetic
        let mate = records.squad?.partner?.mate.character
        personas = (persona, mate?.persona ?? .energetic)
        let kits = try? PlaceholderCharacter.sportKits()
        let kit = records.sports.first.flatMap { top in kits?.kit(for: top.activity, in: SportList.shared.catalog) }
        let idle = try? PlaceholderCharacter.clip("idle", persona: persona)
        if let figure = try? PlaceholderCharacter.figure(wearing: kit?.dress(look) ?? look) {
            let loop = kit.flatMap { try? PlaceholderCharacter.move(for: $0, persona: persona) } ?? idle
            runner = loop.flatMap { try? CharacterPlayer(figure: figure, idle: $0) }
            member = idle.flatMap { try? CharacterPlayer(figure: figure, idle: $0) }
        }
        if let mate, let figure = try? PlaceholderCharacter.figure(wearing: mate.outfit),
            let mateIdle = try? PlaceholderCharacter.clip("idle", persona: mate.persona)
        {
            partner = try? CharacterPlayer(figure: figure, idle: mateIdle)
        } else {
            partner = nil
        }
        heads = [:]
        for mate in [records.squad?.cheersReceived.top?.mate, records.squad?.cheersGiven.top?.mate].compactMap(\.self)
        where heads[mate.member] == nil {
            if let figure = try? PlaceholderCharacter.figure(
                wearing: mate.character?.outfit ?? PlaceholderCharacter.lifter)
            {
                heads[mate.member] = try? CharacterPlayer(figure: figure, idle: .still)
            }
        }
    }

    /// Bumps fists every few seconds, until the page goes.
    func bumpFists() async {
        guard (try? await Task.sleep(for: .seconds(Self.firstBump))) != nil else { return }
        while !Task.isCancelled {
            for (player, persona) in [(member, personas.member), (partner, personas.partner)] {
                if let player, let bump = try? PlaceholderCharacter.clip(for: .bump, persona: persona) {
                    try? player.play(bump)
                }
            }
            guard (try? await Task.sleep(for: .seconds(Self.bumpEvery))) != nil else { return }
        }
    }

    private static let firstBump = 0.6
    private static let bumpEvery = 3.2
}

/// A character on the page: moving, or standing still in a picture.
struct RecordsFigure: View {
    let player: CharacterPlayer?
    let still: Bool

    var body: some View {
        if let player {
            if still {
                let frame = player.restFrame
                CharacterCanvas(drawing: frame.drawing, placements: frame.placements)
                    .aspectRatio(player.drawing.width / player.drawing.height, contentMode: .fit)
                    .accessibilityHidden(true)
            } else {
                CharacterView(player: player)
            }
        } else {
            Color.clear
        }
    }
}

/// A graphite tile: white words on the brand's colour, as 我's glance tiles.
struct RecordsTile<Content: View>: View {
    /// Above the first line; the sides and bottom are the card's padding.
    var topPadding = Space.cardPadding
    var spacing = RecordsTileMetrics.spacing
    @ViewBuilder let content: Content
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(Space.cardPadding)
        .padding(.top, topPadding - Space.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Color(role: .fgOnBrand, in: theme))
        .background(Color(role: .bgBrand, in: theme), in: .rect(cornerRadius: Radius.card))
    }
}

enum RecordsTileMetrics {
    /// Between a tile's lines.
    static let spacing = 10.0
}

/// A tile's name (训练时间), small and spaced out.
struct RecordsLabel: View {
    let text: Text

    var body: some View {
        text.typeStyle(TypeRamp.label).lineLimit(1)
    }
}

/// A big number and its unit (6 天), counting up as the page opens.
struct RecordsNumber: View {
    let value: Int
    let unit: Text
    /// How far the count is, 0 to 1.
    let progress: Double
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
            Text(verbatim: "\(Int((Double(value) * progress).rounded()))")
                .typeStyle(TypeRamp.scoreCard)
                .monospacedDigit()
            unit
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgOnBrandMuted, in: theme))
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(value) ") + unit)
    }
}
#endif
