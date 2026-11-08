#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// The coach's card, opened from a tap on the coach on the home and popped up like a teammate's
/// player card (the approved 教练卡, Tracy 2026-11-05): the same ink stock, with the coach
/// standing on the sideline (a scoreboard, a bench, a water bottle) in its window, the 教练 tag
/// and its title where a member's number goes, then its name, the squad and 「带队 N 天」. A tap
/// turns it over to its 简历 and 逛逛招聘会 (Tracy, 2026-11-08); 换教练 and 解雇 stay on the 简历 on
/// 小队. While the squad is read, or if it can't be, a solid card of the same size stands in.
public struct CoachPlayerCard: View {
    @Bindable private var model: SquadSettingsModel
    /// The squad turned out to have no coach any more (fired from another phone): the app puts
    /// the card away.
    private let gone: () -> Void
    /// 逛逛招聘会, from the card's back: the app puts the card away and opens 教练招聘会.
    private let browse: () -> Void
    @Environment(\.sceneTheme) private var theme

    public init(model: SquadSettingsModel, gone: @escaping () -> Void, browse: @escaping () -> Void) {
        self.model = model
        self.gone = gone
        self.browse = browse
    }

    public var body: some View {
        Group {
            if let settings = model.settings, let hire = settings.coach.hire {
                FlippingCard(hint: .fgOnInk, identifier: "coachCard") {
                    CoachPlayerCardFront(coach: hire.coach, squad: settings.squad.name, day: model.coachDay)
                } back: {
                    CoachPlayerCardBack(coach: hire.coach, browse: browse)
                }
            } else if model.settings != nil {
                Color.clear.onAppear(perform: gone)
            } else if case .failed = model.load {
                standIn { SquadFailed { Task { await model.reload() } } }
            } else {
                standIn { TicketSpinner(on: .light(.bgCanvas)).accessibilityIdentifier("coachCard.loading") }
            }
        }
        .task { await model.reload() }
    }

    private func standIn<Content: View>(_ content: () -> Content) -> some View {
        content()
            .frame(width: TradingCard.size.width, height: TradingCard.size.height)
            .background(Color(role: .bgCanvas, in: theme), in: TradingCard.shape)
    }
}

/// The back: the coach's 简历 (its name and title, catchphrase, 履历, 执教, 风格, 期望待遇 and
/// tags), and at the bottom 逛逛招聘会, a quiet row like the 徽章 one on a member's card.
private struct CoachPlayerCardBack: View {
    let coach: Coach
    let browse: () -> Void
    @Environment(\.sceneTheme) private var theme

    private var ink: Color { Color(role: .fgOnInk, in: theme) }
    private var muted: Color { Color(role: .fgOnInkMuted, in: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoachName(coach: coach, name: TypeRamp.headline, title: TypeRamp.footnote, onInk: true)
            Text("「\(coach.catchphrase)」", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(muted)
                .lineLimit(2)
                .padding(.top, Space.xxs)
            Hairline(on: .ink)
                .padding(.top, Space.s)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: 0) {
                row(Text("履历", bundle: .module)) { Text(verbatim: coach.background) }
                row(Text("执教", bundle: .module)) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                        Text(verbatim: "\(coach.yearsCoaching)").typeStyle(TypeRamp.scoreSmall)
                        Text("年，\(coach.experience)", bundle: .module)
                    }
                }
                row(Text("风格", bundle: .module)) { Text(verbatim: coach.style) }
                row(Text("期望待遇", bundle: .module)) { Text(verbatim: coach.pay) }
            }
            if !coach.tags.isEmpty {
                Text(verbatim: coach.tags.joined(separator: " · "))
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(muted)
                    .lineLimit(2)
                    .padding(.top, Space.s)
            }
            Spacer(minLength: Space.xs)
            Hairline(on: .ink)
            Button(action: browse) {
                HStack(spacing: Space.xs) {
                    Text("逛逛招聘会", bundle: .module)
                        .typeStyle(TypeRamp.calloutEmphasis)
                        .foregroundStyle(ink)
                    Spacer(minLength: Space.xs)
                    Image(systemName: "chevron.right")
                        .font(.system(size: Sizing.smallIcon * 0.8, weight: .semibold))
                        .foregroundStyle(muted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Space.xxs)
                .padding(.vertical, Space.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("coachCard.browse")
        }
        .padding(.horizontal, Space.xs)
        .padding(.top, Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A field: its name on one line, muted, and its value in white, with a hairline under it.
    private func row(_ label: Text, @ViewBuilder value: () -> some View) -> some View {
        Group {
            GridRow {
                label
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(muted)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.vertical, Space.s - 2)
                    .accessibilityIdentifier("coachCard.label")
                value()
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(ink)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Space.s - 2)
            }
            Hairline(on: .ink)
                .gridCellColumns(2)
                .gridCellUnsizedAxes(.horizontal)
        }
    }
}

/// The front: the window with the coach on the sideline, the tag and title at its top left; then
/// the name, the squad and the days it has coached them.
private struct CoachPlayerCardFront: View {
    let coach: Coach
    let squad: String
    let day: Int?
    @Environment(\.sceneTheme) private var theme

    /// The coach's height in the window: taller than a member's, as the card has no numbers row.
    private static let figure = 250.0
    /// The bar under the tag, as a member's card has under its number.
    private static let bar = CGSize(width: 28, height: 3)

    var body: some View {
        VStack(spacing: 0) {
            CoachFigure(coach: coach.id.rawValue) {
                CoachSilhouette(fill: Color(role: .bgInk, in: theme))
                    .frame(height: Self.figure * 0.7)
            }
            .frame(height: Self.figure)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .overlay(alignment: .topLeading) { tagAndTitle }
            .background {
                Color(role: .bgSubtle, in: theme)
                    .overlay {
                        SidelineLines()
                            .stroke(
                                Color(role: .borderBrandFloor, in: theme),
                                style: StrokeStyle(lineWidth: Sizing.selectionStroke, lineCap: .round, lineJoin: .round)
                            )
                            .accessibilityHidden(true)
                    }
            }
            .clipShape(TradingCard.window)
            HStack(alignment: .lastTextBaseline, spacing: Space.xs) {
                VStack(alignment: .leading, spacing: Space.xxs / 2) {
                    Text(verbatim: coach.name)
                        .typeStyle(TypeRamp.title)
                        .foregroundStyle(Color(role: .fgOnInk, in: theme))
                        .lineLimit(1)
                        .accessibilityIdentifier("coachCard.name")
                    Text(verbatim: squad)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let day {
                    Text("带队 \(day) 天", bundle: .module)
                        .typeStyle(TypeRamp.label)
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityIdentifier("coachCard.days")
                }
            }
            .padding(.horizontal, Space.xxs)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xs)
        }
    }

    private var tagAndTitle: some View {
        VStack(alignment: .leading, spacing: Space.xxs + Space.xxs / 2) {
            CoachTag()
            Capsule()
                .fill(Color(role: .fgDefault, in: theme))
                .frame(width: Self.bar.width, height: Self.bar.height)
                .accessibilityHidden(true)
            Text(verbatim: coach.title)
                .typeStyle(TypeRamp.cardTitle)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("coachCard.title")
        }
        .padding(.leading, Space.m)
        .padding(.top, Space.s)
        .padding(.trailing, Space.m)
    }
}

/// The coach's window backdrop, in the faint lines a member's court is drawn in: a scoreboard on
/// two posts, the sideline's floor edge, a bench and a water bottle on the floor. Drawn on a
/// 284 × 380 window and stretched to the window it gets.
private struct SidelineLines: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 284
        let scaleY = rect.height / 380
        func point(_ left: Double, _ top: Double) -> CGPoint {
            CGPoint(x: rect.minX + left * scaleX, y: rect.minY + top * scaleY)
        }
        func box(_ left: Double, _ top: Double, _ width: Double, _ height: Double) -> CGRect {
            CGRect(origin: point(left, top), size: CGSize(width: width * scaleX, height: height * scaleY))
        }
        func line(_ path: inout Path, _ start: (Double, Double), _ end: (Double, Double)) {
            path.move(to: point(start.0, start.1))
            path.addLine(to: point(end.0, end.1))
        }
        var path = Path()
        // The scoreboard and its posts.
        path.addRoundedRect(in: box(26, 60, 232, 70), cornerSize: CGSize(width: 6, height: 6))
        for (start, end) in [(60.0, 100.0), (124, 160), (184, 224)] { line(&path, (start, 95), (end, 95)) }
        line(&path, (40, 130), (40, 160))
        line(&path, (244, 130), (244, 160))
        // The floor's edge, running off toward the viewer.
        line(&path, (0, 240), (284, 240))
        line(&path, (14, 240), (0, 380))
        line(&path, (270, 240), (284, 380))
        // The bench.
        path.addRoundedRect(in: box(20, 268, 244, 12), cornerSize: CGSize(width: 3, height: 3))
        line(&path, (40, 280), (40, 316))
        line(&path, (244, 280), (244, 316))
        // A water bottle on the floor at the right.
        path.addRect(box(220, 248, 14, 20))
        line(&path, (224, 244), (230, 244))
        return path
    }
}
#endif
