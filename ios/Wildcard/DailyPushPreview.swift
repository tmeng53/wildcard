import Contracts
import DailyPushDomain
import DailyPushUI
import DesignSystem
import DesignSystemUI
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
    @State private var opened: PushDestination?

    init(day: Day, now: Date) {
        let opened = _opened
        _model = State(
            initialValue: DailyPushSample.push(empty: day == .empty, now: now).map {
                DailyPushModel(
                    store: DailyPushStore(push: $0, sender: KeptReactions()), arrived: now,
                    looks: DailyPushSample.looks
                ) { destination in
                    opened.wrappedValue = destination
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
            }
            if let opened {
                Text(verbatim: opened.rawValue)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .accessibilityIdentifier("dailyPush.opened")
            }
        }
    }
}

/// The sample has no server: every reaction is kept.
private struct KeptReactions: ReactionSender {
    func setReaction(_ emoji: Emoji?, on checkIn: CheckInID) async throws(DailyPushError) {}
}
