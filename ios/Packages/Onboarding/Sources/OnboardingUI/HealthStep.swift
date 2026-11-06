#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import HealthUI
import OnboardingDomain
import SportsUI
import SwiftUI

/// 连上 Apple 健康, step 4 (Tracy, 2026-11-06): a run as it shows in 动态 once posted from Health,
/// then 连接, which opens HealthKit's own sheet where the member picks what the app reads, and
/// under the run the guide for Fitbit, WHOOP and Oura wearers. Back from the sheet it says
/// 已连接 and goes on with 下一步; 以后再说 skips it.
struct HealthStep: View {
    let model: SignUpModel
    @State private var isGuideOpen = false
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        StepPage(
            step: .health, title: Text("连上 Apple 健康", bundle: .module), character: model.myCharacter,
            onBack: model.back
        ) {
            VStack(alignment: .leading, spacing: Space.m) {
                SampleRun()
                if isConnected {
                    connected
                }
                SyncGuideLink { isGuideOpen = true }
            }
        } actions: {
            if isConnected {
                StepButton(
                    title: Text("下一步", bundle: .module), isWorking: false, isEnabled: true,
                    action: model.finishHealth
                )
                .accessibilityIdentifier("health.done")
            } else {
                StepButton(
                    title: Text("连接", bundle: .module), isWorking: model.isConnectingHealth, isEnabled: true,
                    action: model.connectHealth
                )
                .accessibilityIdentifier("health.connect")
                Button(action: model.finishHealth) {
                    Text("以后再说", bundle: .module)
                }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("health.skip")
            }
        }
        .sheet(isPresented: $isGuideOpen) { SyncGuideSheet() }
        .task { await model.health?.refresh() }
    }

    private var isConnected: Bool { model.health?.isConnected ?? false }

    /// 已连接 Apple 健康: a line with a check, no box around it.
    private var connected: some View {
        Label {
            Text("已连接 Apple 健康", bundle: .module)
                .typeStyle(TypeRamp.calloutEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(role: .fgDefault, in: theme))
        }
        .accessibilityIdentifier("health.connected")
    }
}

/// A morning run from the sample day, drawn as 动态 draws one posted from Health: the route's map,
/// then its 成绩条, then the sport and where it came from.
private struct SampleRun: View {
    @Environment(\.sceneTheme) private var theme
    private let run = SampleHealthLibrary.day(endingNear: Date(timeIntervalSince1970: 0)).last

    var body: some View {
        if let run, let activity = run.activity {
            VStack(spacing: 0) {
                if let route = run.workout.route {
                    WorkoutMap(route: route, activity: activity)
                        .frame(height: 132)
                }
                ScoreStrip(cells: ScoreCell.cells(of: run.workout.summary), activity: activity)
                HStack {
                    activity.name
                    Spacer(minLength: Space.s)
                    Label {
                        Text("Apple 健康", bundle: .module)
                    } icon: {
                        Image(systemName: "heart.fill")
                    }
                }
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xs)
            }
            .background(Color(role: .bgSubtle, in: theme))
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("health.sample")
        }
    }
}
#endif
