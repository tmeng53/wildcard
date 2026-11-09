#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import HealthDomain
import Observation
import SportsUI
import SwiftUI

/// A new workout's reminder, long-pressed (Tracy, 2026-11-08): the workout with its 成绩条 as
/// 设置 shares it, each number struck with a tap, and 发布, which posts it to the squad there and
/// then through its `QuickPosting` port. A workout of no listed sport has no sport to post with,
/// so it offers 去打卡, the compose page, instead.
@MainActor @Observable
public final class QuickPostModel {
    public enum State: Equatable, Sendable {
        case ready
        case sending
        case posted
        /// It goes out when the app next opens.
        case waiting
        case refused
    }

    public let post: QuickPost
    public private(set) var struck: Set<WorkoutCell>
    public private(set) var state = State.ready
    @ObservationIgnored private let poster: any QuickPosting
    @ObservationIgnored private let openApp: @MainActor () -> Void

    /// - Parameter openApp: opens the app on the compose page, as a tap on the reminder does.
    public init(post: QuickPost, poster: any QuickPosting, openApp: @escaping @MainActor () -> Void) {
        self.post = post
        self.poster = poster
        self.openApp = openApp
        struck = post.startsStruck
    }

    var cells: [ScoreCell] { ScoreCell.cells(of: post.workout.summary) }

    public var canPost: Bool { post.activity != nil }

    func toggle(_ cell: WorkoutCell) {
        guard state == .ready else { return }
        if struck.contains(cell) { struck.remove(cell) } else { struck.insert(cell) }
    }

    /// Posts it, with `caption` under it when the member typed one (the reminder's 写一句再发).
    public func send(caption: String = "") async {
        guard state == .ready, canPost else { return }
        state = .sending
        state =
            switch await poster.post(post, struck: struck, caption: caption) {
            case .posted: .posted
            case .waiting: .waiting
            case .refused: .refused
            }
    }

    func open() { openApp() }
}

public struct QuickPostView: View {
    @Environment(\.sceneTheme) private var theme
    private let model: QuickPostModel

    public init(model: QuickPostModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header
            if let activity = model.post.activity {
                ScoreStrip(cells: model.cells, activity: activity, struck: model.struck) { model.toggle($0) }
                HStack {
                    Text("分享到 \(model.post.squadName)", bundle: .module.inAppLanguage)
                    Spacer(minLength: Space.s)
                    Text("点一格可以不发", bundle: .module.inAppLanguage)
                }
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
            }
            action
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(role: .bgCanvas, in: theme))
        .haptic(.checkIn, trigger: model.state == .posted)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quickPost")
    }

    private var header: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: model.post.activity?.symbol ?? Sport.generalSymbol)
            (model.post.activity?.name ?? Text("运动", bundle: .module.inAppLanguage))
                .typeStyle(TypeRamp.headline)
            Spacer(minLength: Space.s)
            HStack(spacing: Space.xxs) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color(role: .fgDanger, in: theme))
                Text("Apple 健康", bundle: .module.inAppLanguage)
                Text(verbatim: "·")
                Text(model.post.workout.startedAt.date, format: .dateTime.hour().minute())
            }
            .typeStyle(TypeRamp.caption)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
        }
        .foregroundStyle(Color(role: .fgDefault, in: theme))
        .lineLimit(1)
    }

    @ViewBuilder private var action: some View {
        switch model.state {
        case .ready, .sending:
            if model.canPost {
                Button {
                    Task { await model.send() }
                } label: {
                    if model.state == .sending {
                        ProgressView()
                    } else {
                        Text("发布", bundle: .module.inAppLanguage)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(.large))
                .disabled(model.state == .sending)
                .accessibilityIdentifier("quickPost.post")
            } else {
                openButton(Text("去打卡", bundle: .module.inAppLanguage))
            }
        case .posted:
            // The app's own done moment: the tickets bounce and the W turns into a check.
            TicketCheck(size: 72, label: Text("已发布", bundle: .module.inAppLanguage)) {
                Text("已发布", bundle: .module.inAppLanguage)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("quickPost.posted")
        case .waiting:
            Text("打开外卡后自动发出", bundle: .module.inAppLanguage)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .frame(maxWidth: .infinity, minHeight: Sizing.primaryControl)
                .accessibilityIdentifier("quickPost.waiting")
        case .refused:
            openButton(Text("没发出去，打开外卡", bundle: .module.inAppLanguage))
        }
    }

    private func openButton(_ title: Text) -> some View {
        Button {
            model.open()
        } label: {
            title
        }
        .buttonStyle(PrimaryButtonStyle(.large))
        .accessibilityIdentifier("quickPost.open")
    }
}
#endif
