import Contracts
import DesignSystem
import DesignSystemUI
import HomeWidgetDomain
import HomeWidgetUI
import SwiftUI

/// The home screen widgets on the sample squad (`-widgets`), at an iPhone's widget sizes and
/// corners, as the home screen shows them. The real ones run in the WildcardWidgets extension,
/// which UI tests can't put on a home screen; this lets them keep screenshots and check nothing
/// spills out of a widget.
struct WidgetPreview: View {
    let now: Date

    var body: some View {
        let day = LocalDay(at: now, in: .current)
        let board = SampleBoard.board(on: day)
        // With a run Health synced: the 打卡 capsule.
        let synced = SampleBoard.board(on: day, workout: true)
        let posted = SampleBoard.board(on: day, posted: true)
        let long = SampleBoard.board(on: day, workout: true, sport: "baseballSoftball")
        let longPosted = SampleBoard.board(on: day, posted: true, sport: "baseballSoftball")
        let coach = SampleBoard.coach
        let open = SampleBoard.board(on: day, coach: coach, challenge: SampleBoard.challenge("慢跑", 3, "公里"))
        let longest = SampleBoard.board(
            on: day, coach: coach, challenge: SampleBoard.challenge("平板支撑加卷腹", 3, "个循环", answer: .accepted))
        let done = SampleBoard.board(
            on: day, coach: coach, challenge: SampleBoard.challenge("深蹲", 4, "组", answer: .accepted, done: true),
            scene: SceneID(rawValue: "track"))
        let noCoach = SampleBoard.board(on: day, scene: SceneID(rawValue: "tennis"))
        let pool = SampleBoard.board(
            on: day, coach: coach, challenge: SampleBoard.challenge("自由泳", 800, "米"), scene: SceneID(rawValue: "pool"))
        ScrollView {
            VStack(spacing: Space.l) {
                HStack(spacing: Space.l) {
                    face(
                        WeekWidget(board: board), size: .small,
                        identifier: "widget.week")
                    face(WidgetNotice(.signedOut), size: .small, identifier: "widget.notice")
                }
                face(
                    SquadWidget(board: board), size: .medium,
                    identifier: "widget.squad")
                HStack(spacing: Space.l) {
                    face(
                        WeekWidget(board: synced), size: .small,
                        identifier: "widget.weekWorkout")
                    // Once posted: the capsule stays, with 已打卡.
                    face(
                        WeekWidget(board: posted), size: .small,
                        identifier: "widget.weekPosted")
                }
                face(
                    SquadWidget(board: synced), size: .medium,
                    identifier: "widget.squadWorkout")
                // A squad of eight: one row of heads over the capsule.
                face(
                    SquadWidget(board: SampleBoard.board(on: day, workout: true, size: 8)),
                    size: .medium, identifier: "widget.squadWorkoutEight")
                // The longest sport name in the list (Baseball and softball): it gives way to its
                // short one and its minutes, never the button.
                HStack(spacing: Space.l) {
                    face(WeekWidget(board: long), size: .small, identifier: "widget.weekWorkoutLong")
                    face(WeekWidget(board: longPosted), size: .small, identifier: "widget.weekPostedLong")
                }
                face(SquadWidget(board: long), size: .medium, identifier: "widget.squadWorkoutLong")
                // Either set to 本周出赛表 in 编辑小组件: the coach behind today's challenge.
                schedule(open, identifier: "widget.schedule")
                // The longest challenge the coach may set, accepted; one done; and no coach yet.
                schedule(longest, identifier: "widget.scheduleLong")
                schedule(done, identifier: "widget.scheduleDone")
                schedule(noCoach, identifier: "widget.scheduleNoCoach")
                // On the squad's scene.
                schedule(pool, identifier: "widget.schedulePool")
            }
            .padding(.vertical, Space.xl)
            .frame(maxWidth: .infinity)
        }
        .background(Color(role: .bgSubtle, in: .gym))
        .environment(\.sceneTheme, .gym)
    }

    /// 本周出赛表 small and medium on `board`, in its scene's colours.
    private func schedule(_ board: WidgetBoard, identifier: String) -> some View {
        VStack(spacing: Space.l) {
            face(ScheduleWidget(board: board, size: .small), size: .small, edgeToEdge: true, identifier: identifier)
            face(
                ScheduleWidget(board: board, size: .medium), size: .medium, edgeToEdge: true,
                identifier: identifier + "Medium")
        }
        .environment(\.sceneTheme, ScheduleWidget.scene(of: board))
    }

    private func face(
        _ content: some View, size: WidgetSize, edgeToEdge: Bool = false, identifier: String
    ) -> some View {
        WidgetFace(size, edgeToEdge: edgeToEdge) { content }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
    }
}
