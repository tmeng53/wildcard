#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The coach's morning note (the approved design): opened by the member, never by itself, it grows
/// over 今天 out of the coach on the sideline, a sheet on a clipboard like 动态's 战术板, with the
/// coach's head, its name and the 教练 tag, whom it is for and the day, the line, and 收下. A tap
/// on 收下 or anywhere around it puts it away.
struct CoachMemberNoteOverlay: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let note: CoachMemberNote
    /// The member's nickname, for 「给 小美 的」; nil before they have one.
    let reader: String?
    /// Where the coach stands on screen (global), which the card grows out of; nil grows it from
    /// its middle.
    let from: CGPoint?
    let putAway: () -> Void
    @State private var head: CharacterPlayer?
    /// Whether the card has grown to its size, once it was measured.
    @State private var isOpen = false
    /// Where in the card it grows from.
    @State private var anchor: UnitPoint = .center

    /// How big the card starts, before it grows out of the coach.
    private static let startScale: Double = 0.2
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
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: { frame in
                guard !isOpen else { return }
                if let from, frame.width > 0, frame.height > 0 {
                    anchor = UnitPoint(x: (from.x - frame.minX) / frame.width, y: (from.y - frame.minY) / frame.height)
                }
                withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { isOpen = true }
            }
            .scaleEffect(isOpen || reduceMotion ? 1 : Self.startScale, anchor: anchor)
            .opacity(isOpen ? 1 : 0)
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
