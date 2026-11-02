#if os(iOS)
import AvatarArt
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// The 小队 tab's row of heads under the squad's name (approved 2026-11-02): every member's face,
/// still, with their name, then the coach's circle (「招聘中」 until the squad hires one; once hired,
/// ringed in ink with a whistle badge and named 「毛头教练」, so no teammate nicknamed 教练 passes
/// for it, as Tracy asked on 2026-11-02) and, while
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
                HeadSpot(name: Text("\(coach.coach.name)教练", bundle: .module), isCoach: true) {
                    CoachHead(coach: coach.coach.id)
                }
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
    /// The coach's name is ink and bold; members' are muted.
    var isCoach = false
    @ViewBuilder let face: () -> Face
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: Space.xxs + 2) {
            face()
                .frame(width: SquadHeadsMetrics.circle, height: SquadHeadsMetrics.circle)
            name
                .typeStyle(isCoach ? TypeRamp.label : TypeRamp.caption)
                .foregroundStyle(Color(role: isCoach ? .fgDefault : .fgMuted, in: theme))
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

/// The squad's coach in a circle ringed in ink, with a whistle badge at its lower right; until
/// its still head, as 教练's thumbnail crops it (an ink silhouette for a coach this build has no
/// character for).
private struct CoachHead: View {
    let coach: CoachID
    @State private var head: CharacterPlayer?
    @Environment(\.sceneTheme) private var theme

    /// The head and shoulders on the coaches' 240 × 320 canvas, as `CoachThumbnail` crops them.
    private static let face = CGRect(x: 44, y: 44, width: 152, height: 152)

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle().fill(Color(role: .bgSubtle, in: theme))
            if let head {
                let frame = head.restFrame
                CharacterCanvas(drawing: frame.drawing, placements: frame.placements, crop: Self.face)
            } else if !CoachCharacter.exists(coach.rawValue) {
                CoachSilhouette(fill: Color(role: .bgInk, in: theme))
                    .frame(width: SquadHeadsMetrics.circle * 0.5)
                    .offset(y: SquadHeadsMetrics.circle * 0.12)
            }
        }
        .clipShape(Circle())
        // A white gap, then the ink ring, as a sticker's edge.
        .padding(SquadHeadsMetrics.ringGap)
        .overlay(Circle().strokeBorder(Color(role: .bgInk, in: theme), lineWidth: Sizing.selectionStroke))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "whistle.fill")
                .font(.system(size: SquadHeadsMetrics.badge * 0.5, weight: .semibold))
                .foregroundStyle(Color(role: .fgOnInk, in: theme))
                .frame(width: SquadHeadsMetrics.badge, height: SquadHeadsMetrics.badge)
                .background(Color(role: .bgInk, in: theme), in: Circle())
                .overlay(Circle().strokeBorder(Color(role: .bgCanvas, in: theme), lineWidth: 2))
                .offset(x: SquadHeadsMetrics.ringGap, y: SquadHeadsMetrics.ringGap)
        }
        .accessibilityHidden(true)
        .task(id: coach) {
            head = nil
            let id = coach.rawValue
            guard CoachCharacter.exists(id) else { return }
            head = try? CharacterPlayer(figure: CoachCharacter.figure(id), idle: CoachCharacter.clip(.idle, coach: id))
        }
    }
}

enum SquadHeadsMetrics {
    /// A head's circle.
    static let circle = 52.0
    /// A head with its name: a little wider than the circle, for the name.
    static let spot = 56.0
    /// The coach's whistle badge.
    static let badge = 22.0
    /// The white gap between the coach's face and its ink ring.
    static let ringGap = 2.0
}
#endif
