#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The coach's morning note (便条, the approved design): it slides up over 今天 from the sideline
/// on the first open after it arrived, a sheet on a clipboard like 动态's 战术板, with the coach's
/// head, its name and the 教练 tag, whom it is for and the day, the line, and 收下. A tap on 收下
/// or anywhere around it puts it away.
struct CoachMemberNoteOverlay: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.locale) private var locale
    let note: CoachMemberNote
    /// The member's nickname, for 「给 小美 的」; nil before they have one.
    let reader: String?
    let putAway: () -> Void
    @State private var head: CharacterPlayer?

    private static let faceSize: Double = 40

    var body: some View {
        ZStack {
            Color(Scrim.tint).opacity(Scrim.tintOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: putAway)
                .accessibilityHidden(true)
            ClipboardCard {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(spacing: Space.s) {
                        MemberHead(player: head, size: Self.faceSize, figure: .coach)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Space.xxs / 2) {
                            HStack(spacing: Space.xs) {
                                Text(verbatim: note.coach.name)
                                    .typeStyle(TypeRamp.calloutEmphasis)
                                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                                CoachTag(.small)
                            }
                            forWhom
                                .typeStyle(TypeRamp.footnote)
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                        }
                        .lineLimit(1)
                    }
                    Text(verbatim: note.text)
                        .typeStyle(TypeRamp.headline)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("today.coachNote.text")
                    Button(action: putAway) {
                        Text(copy: "收下", bundle: .module).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(.regular))
                    .accentTone(.brand)
                    .accessibilityIdentifier("today.coachNote.putAway")
                }
                .padding(.top, Space.l)
                .padding([.horizontal, .bottom], Space.m)
            }
            .padding(.horizontal, Space.pageMargin)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.coachNote")
        }
        .task(id: note.coach.id) {
            let id = note.coach.id.rawValue
            guard CoachCharacter.exists(id) else { return }
            head = try? CharacterPlayer(figure: CoachCharacter.figure(id), idle: CoachCharacter.clip(.idle, coach: id))
        }
    }

    /// 「给 小美 的 · 11月5日 周四」: the day the coach wrote it for.
    private var forWhom: Text {
        let day = Text(note.day.date, format: .dateTime.month(.abbreviated).day().weekday(.abbreviated).locale(locale))
        guard let reader else { return Text(copy: "给你的 · \(day)", bundle: .module) }
        return Text(copy: "给 \(reader) 的 · \(day)", bundle: .module)
    }
}
#endif
