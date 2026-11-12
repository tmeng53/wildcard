#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI
import UIKit

/// The coach's letter (交接信) opened, as the approved 教练交接信 (version 3) draws it: on white, the
/// Wildcard tickets and the date at its head over a hairline, whom it is to, its lines on ruled
/// paper, the 落款 (the coach's head and name), and 收下. Over 今天, and from the coach's 简历.
public struct CoachLetterSheet: View {
    @Environment(\.sceneTheme) private var theme
    let letter: CoachLetter
    /// How much 收下 shows, 0 to 1, while the letter unfolds.
    var button: Double = 1
    let putAway: () -> Void
    @State private var head: CharacterPlayer?
    /// The room the letter's lines have; a letter longer than it scrolls (a long one at large type).
    @State private var room: CGFloat = 0

    public init(letter: CoachLetter, putAway: @escaping () -> Void) {
        self.letter = letter
        self.putAway = putAway
    }

    init(letter: CoachLetter, button: Double, putAway: @escaping () -> Void) {
        self.letter = letter
        self.button = button
        self.putAway = putAway
    }

    /// The letterhead's tickets, and the 落款's head.
    private static let mark: Double = 28
    private static let face: Double = 34
    /// The sheet's padding at its sides and top: the prototype's 20 points.
    private static let inset = Space.m + Space.xxs

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TicketLogo(on: .bgCanvas, ink: .bgBrand)
                    .frame(width: Self.mark, height: Self.mark)
                Spacer()
                Text(verbatim: letter.day.description.replacingOccurrences(of: "-", with: "."))
                    .typeStyle(TypeRamp.ticketDate)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            .padding(.bottom, Space.s)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(role: .borderDefault, in: theme)).frame(height: Sizing.hairline)
            }
            Text(copy: "各位和\(letter.recipient.name)：", bundle: .module)
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .padding(.top, Space.s)
                .padding(.bottom, Space.xs)
            ScrollView {
                RuledLines(lines: letter.lines, minHeight: room)
                    .accessibilityIdentifier("today.letter.text")
            }
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: {
                room = $0
            }
            HStack(spacing: Space.xs) {
                Spacer()
                MemberHead(player: head, size: Self.face, figure: .coach)
                    .accessibilityHidden(true)
                Text(verbatim: letter.from.name)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
            }
            .padding(.top, Space.xs)
            Button(action: putAway) {
                Text(copy: "收下", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(.regular))
            .accentTone(.brand)
            .padding(.top, Space.s)
            .opacity(button)
            .allowsHitTesting(button > 0.5)
            .accessibilityHidden(button < 0.5)
            .accessibilityIdentifier("today.letter.putAway")
        }
        .padding([.horizontal, .top], Self.inset)
        .padding(.bottom, Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(role: .bgCanvas, in: theme))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.letter")
        .task(id: letter.from.id) {
            let id = letter.from.id.rawValue
            guard CoachCharacter.exists(id) else { return }
            head = try? CharacterPlayer(figure: CoachCharacter.figure(id), idle: CoachCharacter.clip(.idle, coach: id))
        }
    }
}

/// The letter's lines on ruled paper: a rule under every line of text, as the prototype's 1.6
/// line height draws them, on down to the sheet's foot.
struct RuledLines: View {
    @Environment(\.sceneTheme) private var theme
    let lines: [String]
    /// The rules run on down to here at least: the sheet's foot.
    let minHeight: CGFloat
    /// One line of text and the room around it: 1.6 times the body's 15 points.
    @ScaledMetric(relativeTo: .callout) private var rule = 24.0

    var body: some View {
        let style = TypeRamp.callout
        let font = UIFontMetrics(forTextStyle: .callout).scaledFont(
            for: UIFont(name: style.face.postScriptName, size: style.size) ?? .systemFont(ofSize: style.size))
        let leading = max(0, rule - font.lineHeight)
        Text(verbatim: lines.joined(separator: "\n"))
            .typeStyle(style)
            .lineSpacing(leading)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .padding(.top, leading / 2)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background {
                Canvas { context, size in
                    var line = rule
                    while line <= size.height {
                        context.fill(
                            Path(CGRect(x: 0, y: line - Sizing.hairline, width: size.width, height: Sizing.hairline)),
                            with: .color(Color(role: .borderDefault, in: theme)))
                        line += rule
                    }
                }
            }
    }
}

/// The coach's letter over 今天, flying in from the coach (`LetterEnvelope`), with 收下 under it.
struct CoachLetterOverlay: View {
    let shown: ShownLetter
    let shownAt: Date
    /// Where the coach stands on screen (global), which the envelope flies out of; nil flies it
    /// from the prototype's place, low on the left.
    let from: CGPoint?
    let clock: () -> Date
    let putAway: () -> Void

    var body: some View {
        LetterEnvelope(
            isSealed: shown.isSealed, shownAt: shownAt, from: from, clock: clock, putAway: putAway,
            address: Text(copy: "给小队和 \(shown.letter.recipient.name) · \(shown.letter.from.name)", bundle: .module)
        ) { button in
            CoachLetterSheet(letter: shown.letter, button: button, putAway: putAway)
        }
    }
}
#endif
