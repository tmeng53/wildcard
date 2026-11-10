#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// What a page or a card shows instead of its content when there is nothing to show yet or it
/// couldn't be read: an optional figure (the character, from `AvatarUI`), one headline and at
/// most one way out, a regular primary button. The one look for every 网络开小差了 and empty
/// state, so each says the same words with the same button. It takes only the space it needs;
/// the caller centres it on the page or sets it in a card.
public struct StateView<Figure: View>: View {
    /// The way out: its words, the accessibility identifier UI tests tap, and what it does.
    public struct Action {
        let title: Text
        let identifier: String
        let run: () -> Void

        public init(_ title: Text, identifier: String, run: @escaping () -> Void) {
            self.title = title
            self.identifier = identifier
            self.run = run
        }

        /// 再试一次.
        public static func retry(identifier: String, run: @escaping () -> Void) -> Action {
            Action(Text(copy: "再试一次", bundle: .module), identifier: identifier, run: run)
        }
    }

    @Environment(\.sceneTheme) private var theme
    private let title: Text
    private let action: Action?
    private let figure: Figure

    public init(_ title: Text, action: Action? = nil, @ViewBuilder figure: () -> Figure) {
        self.title = title
        self.action = action
        self.figure = figure()
    }

    public var body: some View {
        VStack(spacing: Space.m) {
            figure
            title
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .multilineTextAlignment(.center)
            if let action {
                Button(action: action.run) { action.title }
                    .buttonStyle(PrimaryButtonStyle(.regular))
                    .accessibilityIdentifier(action.identifier)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

extension StateView where Figure == EmptyView {
    /// A state with no figure, for a card or a list's place.
    public init(_ title: Text, action: Action? = nil) {
        self.init(title, action: action) { EmptyView() }
    }
}

extension StateView {
    /// 网络开小差了 with 再试一次: the first read didn't reach the server.
    public static func offline(retryIdentifier: String, retry: @escaping () -> Void, @ViewBuilder figure: () -> Figure)
        -> StateView
    {
        StateView(
            Text(copy: "网络开小差了", bundle: .module), action: .retry(identifier: retryIdentifier, run: retry),
            figure: figure)
    }
}

extension StateView where Figure == EmptyView {
    /// 网络开小差了 with 再试一次, without a figure.
    public static func offline(retryIdentifier: String, retry: @escaping () -> Void) -> StateView {
        offline(retryIdentifier: retryIdentifier, retry: retry) { EmptyView() }
    }
}

/// The one line under a change that didn't go out (网络开小差了，没存上), in quiet footnote ink,
/// shown until the next try. Nothing else on the page changes: what the member did stays as
/// they left it.
public struct InlineFailure: View {
    @Environment(\.sceneTheme) private var theme
    private let words: Text

    /// 网络开小差了，没存上.
    public init() {
        self.init(Text(copy: "网络开小差了，没存上", bundle: .module))
    }

    /// Other words for what didn't go out (没发出去).
    public init(_ words: Text) {
        self.words = words
    }

    public var body: some View {
        words
            .typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
    }
}
#endif
