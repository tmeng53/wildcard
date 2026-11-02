#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// The 小队 tab's row of heads under the squad's name (approved 2026-11-02): every member's face,
/// still, with their name, then the coach's circle (「招聘中」 until the squad hires one) and, while
/// the squad has room, 「+ 邀请」, which shares the invite at once. Nothing here moves: the scene
/// and its animations belong to 今天.
struct SquadHeads: View {
    let members: [SquadMemberRow]
    let coach: SquadCoach.Hire?
    let canHireCoach: Bool
    let squad: Squad
    let openSpots: Int
    let openCoach: (CoachRoute) -> Void

    var body: some View {
        FlowRow {
            ForEach(members) { member in
                HeadSpot(name: Text(verbatim: MemberRow.name(of: member))) {
                    MemberHead(character: member.character, size: SquadHeadsMetrics.circle)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("squad.head")
            }
            coachSpot
            if openSpots > 0 {
                ShareLink(item: InviteCard.message(for: squad)) {
                    HeadSpot(name: Text("邀请", bundle: .module)) {
                        DashedCircle(Image(systemName: "plus").font(.system(size: Sizing.icon, weight: .regular)))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("邀请队友", bundle: .module))
                .accessibilityIdentifier("squad.head.invite")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var coachSpot: some View {
        if let coach {
            Button {
                openCoach(.resume(coach.coach))
            } label: {
                HeadSpot(name: Text(verbatim: coach.coach.name)) { CoachHead() }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("squad.head.coach")
        } else {
            let spot = HeadSpot(name: Text("教练", bundle: .module)) {
                DashedCircle(Text("招聘中", bundle: .module).typeStyle(TypeRamp.label))
            }
            if canHireCoach {
                Button {
                    openCoach(.market)
                } label: {
                    spot
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("squad.head.coach")
            } else {
                spot
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("squad.head.coach")
            }
        }
    }
}

/// A circle with a short name under it.
private struct HeadSpot<Face: View>: View {
    let name: Text
    @ViewBuilder let face: () -> Face
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: Space.xxs + 2) {
            face()
                .frame(width: SquadHeadsMetrics.circle, height: SquadHeadsMetrics.circle)
            name
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: SquadHeadsMetrics.spot)
        .contentShape(Rectangle())
    }
}

/// An open spot: a dashed circle on the page with a word or a symbol, styled by the caller, in it.
private struct DashedCircle<Mark: View>: View {
    private let mark: Mark
    @Environment(\.sceneTheme) private var theme

    init(_ mark: Mark) {
        self.mark = mark
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    Color(role: .fgSubtle, in: theme),
                    style: StrokeStyle(lineWidth: Sizing.selectionStroke, dash: [4, 3]))
            mark
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, Space.xxs)
        }
        .accessibilityHidden(true)
    }
}

/// The squad's coach in a circle, until coaches have their own still heads: its ink silhouette.
private struct CoachHead: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle().fill(Color(role: .bgSubtle, in: theme))
            CoachSilhouette(fill: Color(role: .bgInk, in: theme))
                .frame(width: SquadHeadsMetrics.circle * 0.5)
                .offset(y: SquadHeadsMetrics.circle * 0.12)
        }
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

enum SquadHeadsMetrics {
    /// A head's circle.
    static let circle = 52.0
    /// A head with its name: a little wider than the circle, for the name.
    static let spot = 56.0
}
#endif
