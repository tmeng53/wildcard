#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// Marks the words of an @ tag, which `MentionTagRenderer` draws on its capsule.
struct MentionTagRun: TextAttribute {}

/// A teammate's tag is a link that opens their card: `wildcard-mention:<member id>`.
enum MentionLink {
    static let scheme = "wildcard-mention"

    static func url(_ member: MemberID) -> URL? { URL(string: "\(scheme):\(member)") }

    static func member(_ url: URL) -> MemberID? {
        guard url.scheme == scheme, let uuid = UUID(uuidString: String(url.absoluteString.dropFirst(scheme.count + 1)))
        else { return nil }
        return MemberID(uuid)
    }
}

extension MentionedWords {
    /// The words as one text, each 「@名字」 a tag in the scene's accent; a teammate's tag is a
    /// link to their card. Show it with `mentionTags(_:)`, which draws the tags' capsules and
    /// opens the card.
    func text(in theme: SceneTheme) -> Text {
        runs.reduce(Text(verbatim: "")) { text, run in
            switch run {
            case .plain(let words):
                let piece = Text(verbatim: words)
                return Text("\(text)\(piece)", bundle: .module)
            case .tag(let name, let person):
                // Thin spaces either side: the capsule's room around the name.
                var tag = AttributedString("\u{2009}\(name)\u{2009}")
                tag.swiftUI.foregroundColor = Color(role: .fgAccent, in: theme)
                if case .member(let member) = person { tag.link = MentionLink.url(member) }
                let word = Text(tag).fontWeight(.medium).customAttribute(MentionTagRun())
                return Text("\(text)\(word)", bundle: .module)
            }
        }
    }
}

/// Draws each @ tag's capsule under its words, in the scene's soft accent.
struct MentionTagRenderer: TextRenderer {
    let fill: Color

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[MentionTagRun.self] != nil {
                    let bounds = run.typographicBounds.rect.insetBy(dx: 0, dy: 1)
                    context.fill(Capsule().path(in: bounds), with: .color(fill))
                }
                context.draw(run)
            }
        }
    }
}

/// Shows the @ tags of the words in it, and opens a teammate's card when their tag is tapped.
private struct MentionTags: ViewModifier {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel

    func body(content: Content) -> some View {
        content
            .textRenderer(MentionTagRenderer(fill: Color(role: .bgAccentSubtle, in: theme)))
            .tint(Color(role: .fgAccent, in: theme))
            .environment(
                \.openURL,
                OpenURLAction { url in
                    guard let member = MentionLink.member(url) else { return .systemAction }
                    model.openTeammate(member)
                    return .handled
                })
    }
}

extension View {
    /// Draws the @ tags of the words in it as capsules, and opens a teammate's card on a tap of
    /// theirs (the app's `openTeammate`).
    func mentionTags(_ model: FeedModel) -> some View {
        modifier(MentionTags(model: model))
    }
}
#endif
