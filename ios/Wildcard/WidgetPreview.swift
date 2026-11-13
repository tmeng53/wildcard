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
                // Either set to 本周出赛表 in 编辑小组件.
                face(ScheduleWidget(board: board, size: .small), size: .small, identifier: "widget.schedule")
                face(ScheduleWidget(board: board, size: .medium), size: .medium, identifier: "widget.scheduleMedium")
            }
            .padding(.vertical, Space.xl)
            .frame(maxWidth: .infinity)
        }
        .background(Color(role: .bgSubtle, in: .gym))
        .environment(\.sceneTheme, .gym)
    }

    private func face(_ content: some View, size: WidgetSize, identifier: String) -> some View {
        WidgetFace(size) { content }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
    }
}
