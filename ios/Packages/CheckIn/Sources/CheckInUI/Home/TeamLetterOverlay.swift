#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// How the home draws and answers what the team gave on its letter, from the app, which knows
/// the wardrobe's pictures, the member's badges and how to put them on.
public struct TeamLetterPlaces {
    let picture: (TeamPresent) -> AnyView
    let name: (TeamPresent) -> Text
    let wear: ([TeamPresent]) -> Void

    /// - Parameters:
    ///   - picture: a piece on its own, or a team badge's ticket, filling its frame.
    ///   - name: its name in the reader's language.
    ///   - wear: 立刻穿上: the pieces worn and the badge on the member's card, then the wardrobe
    ///     wearing them.
    public init<Picture: View>(
        picture: @escaping (TeamPresent) -> Picture, name: @escaping (TeamPresent) -> Text,
        wear: @escaping ([TeamPresent]) -> Void
    ) {
        self.picture = { AnyView(picture($0)) }
        (self.name, self.wear) = (name, wear)
    }
}

/// The team's letter (感谢信, Tracy 2026-11-11, as the approved mockup draws it): the letterhead
/// of the coach's 交接信, the member's name, its lines on ruled paper, signed 外卡团队, then what
/// the team gave drawn in tiles, with 立刻穿上 and 一会儿再说 (收下 when it gave nothing to wear).
struct TeamLetterSheet: View {
    @Environment(\.sceneTheme) private var theme
    let letter: Broadcast.Letter
    let recipient: String
    let places: TeamLetterPlaces?
    /// How much its buttons show, 0 to 1, while the letter unfolds.
    var button: Double = 1
    let wear: () -> Void
    let putAway: () -> Void
    @State private var room: CGFloat = 0

    private static let mark: Double = 28
    private static let sign: Double = 24
    private static let tile: Double = 64
    private static let inset = Space.m + Space.xxs

    var body: some View {
        let language = [AppLanguage.current.rawValue]
        VStack(alignment: .leading, spacing: 0) {
            TicketLogo(on: .bgCanvas, ink: .bgBrand)
                .frame(width: Self.mark, height: Self.mark)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Space.s)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(role: .borderDefault, in: theme)).frame(height: Sizing.hairline)
                }
                .accessibilityHidden(true)
            Text(copy: "\(recipient)：", bundle: .module)
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .padding(.top, Space.s)
                .padding(.bottom, Space.xs)
            ScrollView {
                RuledLines(
                    lines: letter.lines.localized(in: language).components(separatedBy: "\n"), minHeight: room
                )
                .accessibilityIdentifier("today.teamLetter.text")
            }
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: {
                room = $0
            }
            HStack(spacing: Space.xs) {
                Spacer()
                TicketLogo(on: .bgCanvas, ink: .bgBrand)
                    .frame(width: Self.sign, height: Self.sign)
                    .accessibilityHidden(true)
                Text(copy: "外卡团队", bundle: .module)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
            }
            .padding(.top, Space.xs)
            if let places, !letter.presents.isEmpty {
                presents(places)
            }
            buttons
        }
        .padding([.horizontal, .top], Self.inset)
        .padding(.bottom, Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(role: .bgCanvas, in: theme))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.teamLetter")
    }

    /// What the team gave, side by side: its picture over its name.
    private func presents(_ places: TeamLetterPlaces) -> some View {
        HStack(spacing: Space.xs) {
            ForEach(letter.presents, id: \.self) { present in
                VStack(spacing: Space.xxs) {
                    places.picture(present)
                        .frame(width: Self.tile, height: Self.tile)
                        .accessibilityHidden(true)
                    places.name(present)
                        .typeStyle(TypeRamp.footnoteEmphasis)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .lineLimit(1)
                }
                .padding(Space.xs)
                .frame(maxWidth: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous)
                        .strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, Space.s)
        .accessibilityIdentifier("today.teamLetter.presents")
    }

    @ViewBuilder private var buttons: some View {
        VStack(spacing: 0) {
            if places != nil, !letter.presents.isEmpty {
                Button(action: wear) {
                    Text(copy: "立刻穿上", bundle: .module).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(.regular))
                .accentTone(.brand)
                .accessibilityIdentifier("today.teamLetter.wear")
                Button(action: putAway) {
                    Text(copy: "一会儿再说", bundle: .module)
                }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("today.teamLetter.later")
            } else {
                Button(action: putAway) {
                    Text(copy: "收下", bundle: .module).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(.regular))
                .accentTone(.brand)
                .accessibilityIdentifier("today.teamLetter.putAway")
            }
        }
        .padding(.top, Space.s)
        .frame(maxWidth: .infinity)
        .opacity(button)
        .allowsHitTesting(button > 0.5)
        .accessibilityHidden(button < 0.5)
    }
}

/// The team's letter over 今天, flying in sealed from low on the left (`LetterEnvelope`) when new,
/// simply shown when opened again from 通知.
struct TeamLetterOverlay: View {
    let model: TodayModel
    let shown: TodayModel.ShownTeamLetter

    var body: some View {
        if let letter = shown.broadcast.letter {
            let recipient = model.teamLetterRecipient
            LetterEnvelope(
                isSealed: shown.isSealed, shownAt: shown.shownAt, from: nil, clock: model.now,
                putAway: model.putAwayTeamLetter, address: Text(copy: "给 \(recipient) · 外卡团队", bundle: .module)
            ) { button in
                TeamLetterSheet(
                    letter: letter, recipient: recipient, places: model.teamLetterPlaces, button: button,
                    wear: model.wearTeamLetter, putAway: model.putAwayTeamLetter)
            }
        }
    }
}
#endif
