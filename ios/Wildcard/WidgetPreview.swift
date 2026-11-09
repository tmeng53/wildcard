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
        // With a run Health synced: the 打卡 capsule. Its 打卡 is an App Intent in the widget;
        // here it is only its label.
        let synced = SampleBoard.board(on: day, workout: true)
        let posted = SampleBoard.board(on: day, posted: true)
        ScrollView {
            VStack(spacing: Space.l) {
                HStack(spacing: Space.l) {
                    face(
                        WeekWidget(board: board) { _ in PostWorkoutLabel() }, width: Self.small,
                        identifier: "widget.week")
                    face(WidgetNotice(.signedOut), width: Self.small, identifier: "widget.notice")
                }
                face(
                    SquadWidget(board: board) { _ in PostWorkoutLabel() }, width: Self.medium,
                    identifier: "widget.squad")
                HStack(spacing: Space.l) {
                    face(
                        WeekWidget(board: synced) { _ in PostWorkoutLabel() }, width: Self.small,
                        identifier: "widget.weekWorkout")
                    // Once posted: the capsule stays, with 已打卡.
                    face(
                        WeekWidget(board: posted) { _ in PostWorkoutLabel() }, width: Self.small,
                        identifier: "widget.weekPosted")
                }
                face(
                    SquadWidget(board: synced) { _ in PostWorkoutLabel() }, width: Self.medium,
                    identifier: "widget.squadWorkout")
                // A squad of eight: one row of heads over the capsule.
                face(
                    SquadWidget(board: SampleBoard.board(on: day, workout: true, size: 8)) { _ in PostWorkoutLabel() },
                    width: Self.medium, identifier: "widget.squadWorkoutEight")
            }
            .padding(.vertical, Space.xl)
            .frame(maxWidth: .infinity)
        }
        .background(Color(role: .bgSubtle, in: .gym))
        .environment(\.sceneTheme, .gym)
    }

    private func face(_ content: some View, width: Double, identifier: String) -> some View {
        content
            .padding(Space.m)
            .frame(width: width, height: Self.small)
            .background(Color(role: .bgCanvas, in: .gym))
            .clipShape(RoundedRectangle(cornerRadius: Radius.menu - 2, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
    }

    /// An iPhone's small widget is 170 points square on a 6.1" to 6.3" phone, a medium one 364
    /// by 170, with 16 points of margin inside.
    private static let small: Double = 170
    private static let medium: Double = 364
}
