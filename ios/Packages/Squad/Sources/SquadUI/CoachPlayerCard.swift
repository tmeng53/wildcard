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
/// and its title where a member's number goes, then its name, the squad and 「带队 N 天」. It has
/// no back and no buttons; 换教练 and 解雇 stay on its 简历 on 小队. While the squad is read, or if
/// it can't be, a solid card of the same size stands in.
public struct CoachPlayerCard: View {
    @Bindable private var model: SquadSettingsModel
    /// The squad turned out to have no coach any more (fired from another phone): the app puts
    /// the card away.
    private let gone: () -> Void
    @Environment(\.sceneTheme) private var theme

    public init(model: SquadSettingsModel, gone: @escaping () -> Void) {
        self.model = model
        self.gone = gone
    }

    public var body: some View {
        Group {
            if let settings = model.settings, let hire = settings.coach.hire {
                CoachPlayerCardFront(coach: hire.coach, squad: settings.squad.name, day: model.coachDay)
                    .tradingCardStock()
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("coachCard")
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
