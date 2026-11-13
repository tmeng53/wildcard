#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// What the squad's coach said that the member hasn't seen yet (Tracy, 2026-11-13, option 1): the
/// coach's name and the start of its newest line.
public struct CoachNewsLine: Sendable, Hashable {
    /// The coach's name: 「毛头」.
    public let name: String
    /// The start of what it said; the row cuts it to one line.
    public let line: String

    public init(name: String, line: String) {
        (self.name, self.line) = (name, line)
    }
}

extension SquadCard {
    /// The coach's row, the squad page's last row while the coach said something the member hasn't
    /// seen and no accepted challenge takes the place: the coach's head with a dot, its name and
    /// line, and a chevron; a tap anywhere on it runs `open` (the coach's page).
    public func coachNews<Head: View>(
        _ news: CoachNewsLine?, open: @escaping () -> Void, @ViewBuilder head: () -> Head
    ) -> Self {
        var card = self
        card.coachNews = news
        card.coachNewsHead = AnyView(head())
        card.openCoachNews = open
        return card
    }
}

/// The coach's row on the squad page, past a hairline like the challenge row and as tall: the
/// coach's head with the graphite dot its phone shows on the scene, its name over the start of its
/// newest line, and a chevron.
struct CoachNewsRow: View {
    @Environment(\.sceneTheme) private var theme
    let news: CoachNewsLine
    /// The coach's head; without one, a graphite disc stands in.
    let head: AnyView?
    let open: () -> Void

    /// The dot on the head's upper right, and the ring that cuts it from the head.
    private static let dot: Double = 10
    private static let dotRing: Double = 2

    var body: some View {
        VStack(spacing: Space.s) {
            Rectangle()
                .fill(Color(role: .borderDefault, in: theme))
                .frame(height: Sizing.hairline)
            Button(action: open) {
                HStack(spacing: Space.s) {
                    coach
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: news.name)
                            .typeStyle(TypeRamp.calloutEmphasis)
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                        Text(verbatim: news.line)
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .fgMuted, in: theme))
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: Sizing.smallIcon - 2, weight: .semibold))
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: news.name))
            .accessibilityValue(Text(verbatim: news.line))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("squadcard.coachNews")
        }
        .padding(.top, Space.s)
    }

    private var coach: some View {
        Group {
            if let head {
                head
            } else {
                Circle().fill(Color(role: .bgBrand, in: theme))
            }
        }
        .frame(width: ChallengeRowLayout.head, height: ChallengeRowLayout.head)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color(role: .bgBrand, in: theme))
                .frame(width: Self.dot, height: Self.dot)
                .padding(Self.dotRing)
                .background(Color(role: .bgCanvas, in: theme), in: Circle())
                .offset(x: Self.dotRing, y: -Self.dotRing)
        }
        .accessibilityHidden(true)
    }
}
#endif
