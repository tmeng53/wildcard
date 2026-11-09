#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import HealthDomain
import HomeWidgetDomain
import SwiftUI

/// 小队今天, the medium widget: the squad's week as the squad card's first page counts it, with
/// 打卡 under it, and on the right who checked in today, ringed as on home, under the coach, who
/// wears its ink dot while it has a card I haven't seen. While Health has a workout to post, its
/// 打卡 capsule runs across the foot in place of 打卡, and stays with 已打卡 once it is posted.
public struct SquadWidget<Post: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let board: WidgetBoard
    private let post: (ImportedWorkout) -> Post

    /// - Parameter post: the capsule's 打卡 for the board's workout.
    public init(board: WidgetBoard, @ViewBuilder post: @escaping (ImportedWorkout) -> Post) {
        self.board = board
        self.post = post
    }

    public var body: some View {
        VStack(spacing: Space.xs) {
            HStack(alignment: .top, spacing: Space.m) {
                week
                today
                    .frame(width: WidgetMetrics.ringed * 4 + Space.xxs * 3)
            }
            if let workout = board.workout {
                Spacer(minLength: 0)
                WorkoutCapsule(workout: workout, size: .medium) { post(workout) }
            } else if let posted = board.postedWorkout {
                Spacer(minLength: 0)
                WorkoutCapsule(workout: posted, size: .medium) { PostedWorkoutLabel() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Whether the capsule runs across the foot, where 打卡 would be.
    private var hasCapsule: Bool { board.workout != nil || board.postedWorkout != nil }

    private var week: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(Text(copy: "小队本周目标", bundle: .module))
            Text(verbatim: board.squadName)
                .typeStyle(TypeRamp.calloutEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs / 2) {
                Score(count: board.squad.trainedDays, goal: board.squad.plannedDays, size: .card)
                Text(copy: "次", bundle: .module)
                    .typeStyle(TypeRamp.denominator(of: TypeRamp.scoreCard))
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
            }
            .lineLimit(1)
            DayCells(filled: board.squad.trainedDays, total: board.squad.plannedDays)
                .padding(.top, Space.xxs)
            if !hasCapsule {
                Spacer(minLength: Space.xs)
                checkIn
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var checkIn: some View {
        Link(destination: WidgetLink.checkIn.url) {
            Label {
                Text(copy: "打卡", bundle: .module)
            } icon: {
                Image(systemName: "plus")
            }
            .typeStyle(TypeRamp.footnoteEmphasis)
            .foregroundStyle(Color(role: .fgOnInk, in: theme))
            .padding(.horizontal, Space.s)
            .frame(height: WidgetMetrics.button)
            .background(Color(role: .bgInk, in: theme), in: Capsule())
        }
        .accessibilityIdentifier("widget.checkIn")
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: 0) {
                Text(copy: "今天 \(board.checkedInToday)/\(board.mates.count)", bundle: .module)
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let coach = board.coach { coachHead(coach) }
            }
            .frame(height: WidgetMetrics.coachHead)
            Grid(horizontalSpacing: Space.xxs, verticalSpacing: Space.xxs) {
                ForEach(rows, id: \.first?.member) { row in
                    GridRow {
                        ForEach(row, id: \.member) { mate in
                            MemberHead(
                                player: WidgetCharacter.player(mate.look), size: WidgetMetrics.head,
                                status: ring(mate))
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(copy: "今天 \(board.checkedInToday)/\(board.mates.count)", bundle: .module))
    }

    @ViewBuilder private func coachHead(_ coach: CoachID) -> some View {
        MemberHead(player: Self.player(of: coach), size: WidgetMetrics.coachHead, figure: .coach)
            .overlay(alignment: .topTrailing) {
                if board.coachHasNews {
                    Circle()
                        .fill(Color(role: .fgDefault, in: theme))
                        .frame(width: WidgetMetrics.dot, height: WidgetMetrics.dot)
                        .overlay { Circle().stroke(Color(role: .bgCanvas, in: theme), lineWidth: Sizing.hairline * 2) }
                        .offset(x: 1, y: -1)
                }
            }
    }

    /// The coach standing still; nil for a coach this build has no art for, an empty head.
    private static func player(of coach: CoachID) -> CharacterPlayer? {
        let id = coach.rawValue
        guard CoachCharacter.exists(id) else { return nil }
        return try? CharacterPlayer(figure: CoachCharacter.figure(id), idle: CoachCharacter.clip(.idle, coach: id))
    }

    /// The squad, up to eight, four to a row; one row, those who checked in first, while the
    /// capsule takes the foot, so the widget keeps its height (今天 x/y still counts everyone).
    private var rows: [[WidgetBoard.Mate]] {
        let shown = Array(board.mates.prefix(hasCapsule ? 4 : 8))
        return stride(from: 0, to: shown.count, by: 4).map { Array(shown[$0..<min($0 + 4, shown.count)]) }
    }

    private func ring(_ mate: WidgetBoard.Mate) -> RingStatus {
        switch mate.status {
        case .checkedIn: .done
        case .restDay: .restDay
        case .notYet: .open
        }
    }
}
#endif
