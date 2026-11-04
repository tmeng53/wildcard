#if canImport(SwiftUI)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// Someone's head in a circle, the one face of a member (or the coach) wherever the app shows a
/// person small: rows, comments, reactions, who reacted, the squad's row. 24, 32 and 44 points
/// are the usual sizes (`Sizing.characterHead` is 28).
///
/// - `rim`: `.mist` (a teammate, on a white disc with a mist ring), `.coach` (the coach, a
///   graphite ring so it never reads as a teammate), `.cutout(role)` (heads overlapping in a
///   `HeadStack`: a rim in the background's colour between them) or `.none`.
/// - `status`: today's ring (`StatusRing`) around the head instead of the rim: grey until they
///   check in, the scene's colour once they did, grey with a moon on a rest day.
/// - `emoji`: the reaction it wears at its lower right.
/// - `showsCoachTag`: the small 「教练」 tag under the head; off unless asked for (the coach's
///   name usually carries it).
public struct MemberHead: View {
    public enum Rim: Sendable, Hashable {
        case mist
        case coach
        case cutout(ColorRole)
        case none
    }

    /// Whose canvas the player draws on: a member's rig or a coach's.
    public enum Figure: Sendable {
        case member
        case coach
    }

    @Environment(\.sceneTheme) private var theme
    private let player: CharacterPlayer?
    private let size: Double
    private let figure: Figure
    private let rim: Rim
    private let status: RingStatus?
    private let emoji: String?
    private let showsCoachTag: Bool

    /// The face on a member's 240 by 320 canvas.
    static let memberFace = CGRect(x: 40, y: 74, width: 160, height: 160)
    /// The head on a coach's 240 by 320 canvas.
    static let coachFace = CGRect(x: 50, y: 46, width: 140, height: 140)
    /// The coach's graphite ring.
    private static let coachRing: Double = 1.5

    public init(
        player: CharacterPlayer?, size: Double, figure: Figure = .member, rim: Rim? = nil, status: RingStatus? = nil,
        emoji: String? = nil, showsCoachTag: Bool = false
    ) {
        self.player = player
        self.size = size
        self.figure = figure
        self.rim = rim ?? (figure == .coach ? .coach : .mist)
        self.status = status
        self.emoji = emoji
        self.showsCoachTag = showsCoachTag
    }

    public var body: some View {
        Group {
            if let status {
                StatusRing(status: status, avatarSize: size) { face }
            } else {
                disc
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let emoji {
                Text(verbatim: emoji)
                    .font(.system(size: size * 12 / 26))
                    .offset(x: size * 0.12, y: size * 0.08)
            }
        }
        .overlay(alignment: .bottom) {
            if showsCoachTag {
                CoachTag(.small).offset(y: CoachTag.Size.small.height / 2)
            }
        }
        .accessibilityHidden(true)
    }

    private var disc: some View {
        Circle()
            .fill(Color(role: .bgCanvas, in: theme))
            .overlay { face.padding(rim == .none ? 0 : Sizing.ringGap) }
            .clipShape(Circle())
            .overlay { rimStroke }
            .frame(width: size, height: size)
    }

    @ViewBuilder private var face: some View {
        if let player {
            let frame = player.restFrame
            CharacterCanvas(
                drawing: frame.drawing, placements: frame.placements,
                crop: figure == .coach ? Self.coachFace : Self.memberFace
            )
            .aspectRatio(1, contentMode: .fit)
        }
    }

    @ViewBuilder private var rimStroke: some View {
        switch rim {
        case .mist:
            Circle().stroke(Color(role: .bgSubtle, in: theme), lineWidth: Sizing.ringGap)
        case .coach:
            Circle().strokeBorder(Color(role: .bgInk, in: theme), lineWidth: Self.coachRing)
        case .cutout(let role):
            Circle().strokeBorder(Color(role: role, in: theme), lineWidth: Sizing.selectionStroke)
        case .none:
            EmptyView()
        }
    }
}

/// Heads overlapping in a row, each a little over the one before (the squad on 你的小队, who
/// patted on the 6pm push), with a rim in the background's colour between them, and 「+N」 for
/// those past `limit`.
public struct HeadStack: View {
    @Environment(\.sceneTheme) private var theme
    private let players: [CharacterPlayer?]
    private let size: Double
    private let background: ColorRole
    private let limit: Int

    public init(_ players: [CharacterPlayer?], size: Double, on background: ColorRole, limit: Int = 5) {
        self.players = players
        self.size = size
        self.background = background
        self.limit = max(limit, 1)
    }

    public var body: some View {
        HStack(spacing: -Space.xxs) {
            ForEach(Array(players.prefix(limit).enumerated()), id: \.offset) { _, player in
                MemberHead(player: player, size: size, rim: .cutout(background))
            }
            if players.count > limit {
                Text(verbatim: "+\(players.count - limit)")
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .frame(width: size, height: size)
                    .background(Color(role: .bgSubtle, in: theme), in: Circle())
                    .overlay {
                        Circle().strokeBorder(Color(role: background, in: theme), lineWidth: Sizing.selectionStroke)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
