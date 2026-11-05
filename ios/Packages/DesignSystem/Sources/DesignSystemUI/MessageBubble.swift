#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Whose a message is, which sets its bubble.
public enum MessageStyle: Sendable {
    case teammate
    case mine
    case coach
}

/// A message's bubble, as iMessage draws one (the squad chat, and anywhere a message is shown):
/// a teammate's on the light grey, mine in the brand's graphite, the coach's white with an ink
/// edge. Solid, never glass, so the words read over anything.
public struct MessageBubble<Content: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let style: MessageStyle
    private let content: Content

    static var radius: Double { 18 }
    static var edge: Double { 1.5 }

    public init(_ style: MessageStyle, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    public var body: some View {
        content
            .typeStyle(TypeRamp.body)
            .foregroundStyle(Color(role: style == .mine ? .fgOnBrand : .fgDefault, in: theme))
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs + 1)
            .frame(minHeight: Sizing.control - 6)
            .background(Self.fill(style, theme), in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .overlay {
                if style == .coach {
                    RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                        .strokeBorder(Color(role: .fgDefault, in: theme), lineWidth: Self.edge)
                }
            }
    }

    static func fill(_ style: MessageStyle, _ theme: SceneTheme) -> Color {
        switch style {
        case .teammate: Color(role: .bgSubtle, in: theme)
        case .mine: Color(role: .bgBrand, in: theme)
        case .coach: Color(role: .bgCanvas, in: theme)
        }
    }
}

extension MessageBubble where Content == Text {
    /// A bubble of words.
    public init(_ style: MessageStyle, text: String) {
        self.init(style) { Text(verbatim: text) }
    }
}

/// What a reply replies to, over its bubble (iMessage's): the original, faded and small on one
/// line, and a thin line curving down from it to the reply.
public struct ReplyReference: View {
    @Environment(\.sceneTheme) private var theme
    private let text: String
    private let style: MessageStyle
    private let leading: Bool

    /// `leading` when the reply sits at the left (a teammate's or the coach's), so the line
    /// comes down on that side.
    public init(_ text: String, style: MessageStyle, leading: Bool = true) {
        self.text = text
        self.style = style
        self.leading = leading
    }

    public var body: some View {
        HStack(spacing: 0) {
            if leading { line }
            Text(verbatim: text)
                .typeStyle(TypeRamp.footnote)
                .lineLimit(1)
                .foregroundStyle(Color(role: style == .mine ? .fgOnBrand : .fgDefault, in: theme))
                .padding(.horizontal, Space.s - 2)
                .padding(.vertical, Space.xxs + 1)
                .background(
                    MessageBubble<Text>.fill(style, theme),
                    in: RoundedRectangle(cornerRadius: MessageBubble<Text>.radius, style: .continuous)
                )
                .overlay {
                    if style == .coach {
                        RoundedRectangle(cornerRadius: MessageBubble<Text>.radius, style: .continuous)
                            .strokeBorder(Color(role: .fgDefault, in: theme), lineWidth: MessageBubble<Text>.edge)
                    }
                }
                .frame(maxWidth: 220, alignment: leading ? .leading : .trailing)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(0.55)
            if !leading { line }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("回复", bundle: .module))
        .accessibilityValue(Text(verbatim: text))
    }

    /// From the original's middle, out and down to the reply under it.
    private var line: some View {
        ReplyLine(leading: leading)
            .stroke(
                Color(role: .fgSubtle, in: theme),
                style: StrokeStyle(lineWidth: Sizing.selectionStroke, lineCap: .round)
            )
            .frame(width: Space.s, height: Space.s)
            .offset(y: Space.xs)
            .padding(.horizontal, Space.xxs)
    }
}

private struct ReplyLine: Shape {
    let leading: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner = min(rect.width, rect.height)
        if leading {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.minY + corner), control: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + corner), control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        return path
    }
}

/// The emoji on a message's top corner, as iMessage puts them: the most left first, and how many
/// left emoji. A tap shows who reacted.
public struct ReactionBadge: View {
    @Environment(\.sceneTheme) private var theme
    private let emoji: [String]
    private let count: Int
    private let action: () -> Void

    /// `emoji` the most left first; only the first two show.
    public init(emoji: [String], count: Int, action: @escaping () -> Void) {
        self.emoji = emoji
        self.count = count
        self.action = action
    }

    public var body: some View {
        let all = emoji.joined()
        return Button(action: action) {
            HStack(spacing: Space.xxs / 2) {
                Text(verbatim: emoji.prefix(2).joined())
                if count > 1 {
                    Text(verbatim: "\(count)").typeStyle(TypeRamp.footnoteEmphasis)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .padding(.horizontal, Space.xs)
            .frame(height: Sizing.smallTag)
            .background(Color(role: .bgCanvas, in: theme), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline))
            .padding(2)
            .background(Color(role: .bgCanvas, in: theme), in: Capsule())
            .frame(minHeight: Sizing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(verbatim: "\(all) \(count)"))
        .accessibilityHint(Text("看谁回应了", bundle: .module))
    }
}

/// How many are unread, in the brand's graphite with a white edge: on a round button's corner (the
/// chat's entry). Never red. Over 99 reads 99+.
public struct CountBadge: View {
    @Environment(\.sceneTheme) private var theme
    private let count: Int

    public init(_ count: Int) {
        self.count = count
    }

    public var body: some View {
        Text(verbatim: count > 99 ? "99+" : "\(count)")
            .typeStyle(TypeRamp.label)
            .monospacedDigit()
            .foregroundStyle(Color(role: .fgOnBrand, in: theme))
            .padding(.horizontal, Space.xxs + 1)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color(role: .bgBrand, in: theme), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(role: .bgCanvas, in: theme), lineWidth: 2))
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// A 44-point round button in the system's interactive Liquid Glass tinted in the scene's colour,
/// with a white glyph and, when there is any, an unread count on its corner: the chat's entry
/// beside 打卡 on 今天.
public struct GlassRoundButton: View {
    @Environment(\.sceneTheme) private var theme
    private let label: Text
    private let systemImage: String
    private let count: Int
    private let action: () -> Void

    public init(_ label: Text, systemImage: String, count: Int = 0, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.count = count
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Sizing.icon, weight: .semibold))
                .foregroundStyle(Color(role: .fgOnAccent, in: theme))
                .frame(width: Sizing.control, height: Sizing.control)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .glassEffect(.regular.tint(Color(role: .bgAccent, in: theme)).interactive(), in: Circle())
        .overlay(alignment: .topTrailing) {
            if count > 0 {
                CountBadge(count).offset(x: 6, y: -4)
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(count > 0 ? Text("\(count) 条未读", bundle: .module) : Text(verbatim: ""))
    }
}

/// Whom to @, over the composer: each person's head and name, the coach first with the 教练 tag,
/// the first row lit (what return picks). The caller draws the heads.
public struct PersonPicker<Person: Identifiable, Head: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let people: [Person]
    private let name: (Person) -> String
    private let isCoach: (Person) -> Bool
    private let head: (Person) -> Head
    private let identifier: String
    private let pick: (Person) -> Void

    private static var row: Double { 40 }
    private static var visibleRows: Double { 4.5 }

    public init(
        _ people: [Person], name: @escaping (Person) -> String, isCoach: @escaping (Person) -> Bool,
        identifier: String, @ViewBuilder head: @escaping (Person) -> Head, pick: @escaping (Person) -> Void
    ) {
        self.people = people
        self.name = name
        self.isCoach = isCoach
        self.head = head
        self.identifier = identifier
        self.pick = pick
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    Button {
                        pick(person)
                    } label: {
                        HStack(spacing: Space.s - 2) {
                            head(person)
                            Text(verbatim: name(person))
                                .typeStyle(TypeRamp.body)
                                .foregroundStyle(Color(role: .fgDefault, in: theme))
                                .lineLimit(1)
                            if isCoach(person) { CoachTag(.small) }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Space.xs)
                        .frame(height: Self.row)
                        .background {
                            if index == 0 {
                                RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
                                    .fill(Color(role: .bgSubtle, in: theme))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("\(identifier).\(index)")
                }
            }
            .padding(Space.xxs + 2)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: Self.row * Self.visibleRows + 2 * (Space.xxs + 2))
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("提到谁", bundle: .module))
    }
}
#endif
