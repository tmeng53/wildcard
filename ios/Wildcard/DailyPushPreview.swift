import Contracts
import DailyPushDomain
import DailyPushUI
import DesignSystem
import DesignSystemUI
import Observation
import SwiftUI

/// The 6pm push's long-press view on the sample squad (`-daily-push full` or `empty`), laid out
/// as iOS shows a notification's own view: a rounded card near the top of a dimmed screen,
/// scrolling when it is longer than the screen. The real one runs in the WildcardPushReact
/// extension, which UI tests can't open; this lets them react, open every emoji and keep
/// screenshots.
struct DailyPushPreview: View {
    enum Day: String {
        case full, empty
    }

    @State private var model: DailyPushModel?
    /// Where the view last asked to open the app, for UI tests to check.
    @State private var opened: Opened

    init(day: Day, now: Date) {
        // A reference the model's callback shares with the view: a `State` copied before SwiftUI
        // installs it isn't connected to the view, so writing to it would change nothing.
        let opened = Opened()
        _opened = State(initialValue: opened)
        _model = State(
            initialValue: DailyPushSample.push(empty: day == .empty, now: now).map {
                DailyPushModel(
                    store: DailyPushStore(push: $0, sender: KeptReactions(), now: { Date() }), arrived: now,
                    looks: DailyPushSample.looks
                ) { destination in
                    opened.destination = destination
                }
            })
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(role: .bgBrand, in: .gym).opacity(0.85).ignoresSafeArea()
            if let model {
                // A long one scrolls, as iOS lets a notification's own view do.
                ScrollView {
                    DailyPushView(model: model)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card + 8, style: .continuous))
                        .padding(.horizontal, Space.xs)
                        .padding(.vertical, Space.xs)
                }
                // Scrolled, the card stays below the status bar, as iOS keeps a notification's view.
                .clipped()
            }
            if let destination = opened.destination {
                Text(verbatim: destination.rawValue)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .accessibilityIdentifier("dailyPush.opened")
            }
        }
    }
}

/// Where the preview's push view last asked to open the app.
@MainActor @Observable
private final class Opened {
    var destination: PushDestination?
}

/// The sample has no server: every reaction is kept.
private struct KeptReactions: ReactionSender {
    func setReaction(_ emoji: Emoji?, on checkIn: CheckInID) async throws(DailyPushError) {}
}
