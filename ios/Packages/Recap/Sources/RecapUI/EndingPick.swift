#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import ScenePickDomain
import ScenePickUI
import SwiftUI

/// 这一周 for whoever picks next week's scene (冠军开箱, approved 2026-10-22): the squad's count a
/// size down, 冠军专属's sticker under it, the squad standing in a row above 存图 and 排下周.
/// A phone too short for all of it leaves the row out; the sticker is never part of 存图.
struct EndingPickPage: View {
    let ending: Ending
    let page: PageContext
    let actions: EndingActions
    let picker: ScenePicker
    let onPicked: (Unboxing, SceneTheme) -> Void
    @Environment(\.sceneTheme) private var theme
    @State private var players: [CharacterPlayer] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            Ground(height: Self.panel)
            ViewThatFits(in: .vertical) {
                column(standing: true)
                column(standing: false)
            }
            // The panel runs to the screen's edge, as in the design, under the home indicator.
            .ignoresSafeArea(edges: .bottom)
        }
        .task(id: page.lineup) { players = Self.players(page.lineup, in: page.cast) }
    }

    private func column(standing: Bool) -> some View {
        VStack(spacing: 0) {
            header
            SceneSticker(picker: picker, onPicked: onPicked)
                // The page moves on with a tap anywhere else; on the sticker a tap only picks.
                .contentShape(Rectangle())
                .onTapGesture {}
                .padding(.top, Space.l)
            Spacer(minLength: 0)
            if standing {
                SquadLineup(players: players)
                    .frame(height: Self.lineupHeight)
                    .padding(.bottom, -Self.standIn)
                    .zIndex(1)
            }
            EndingButtons(actions: actions)
                .padding(.top, Space.l - Space.xxs)
                .frame(height: Self.panel, alignment: .top)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("全队", bundle: .module)
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgAccent, in: theme))
                headline.typeStyle(TypeRamp.title)
                    .accessibilityAddTraits(.isHeader)
            }
            .accessibilityElement(children: .combine)
            Score(count: Int((Double(ending.done) * counted).rounded()), goal: ending.plan, size: .ending)
                .padding(.top, Space.s)
            line.typeStyle(TypeRamp.footnoteEmphasis)
                .padding(.top, Space.xs)
        }
        .foregroundStyle(Color(role: .fgOnScene, in: theme))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.m)
        .padding(.top, Space.m)
    }

    /// The count fills over the first second, as on the page without the pick.
    private var counted: Double {
        let fraction = page.ramp(0.1, 1.0)
        return 1 - (1 - fraction) * (1 - fraction)
    }

    private var headline: Text {
        ending.headline.map { Text(verbatim: $0) } ?? Text("这一周", bundle: .module)
    }

    private var line: Text {
        if let line = ending.line { return Text(verbatim: line) }
        return ending.isHit ? Text("全队达标", bundle: .module) : Text("还差 \(ending.shortBy) 次", bundle: .module)
    }

    /// Each member playing their own idle, in the story's lineup order.
    private static func players(_ lineup: [MemberID], in cast: StoryCast) -> [CharacterPlayer] {
        lineup.enumerated().compactMap { index, id in
            guard let member = cast[id], let figure = try? PlaceholderCharacter.figure(wearing: member.look),
                let idle = try? PlaceholderCharacter.clip("idle", persona: member.persona)
            else { return nil }
            return try? CharacterPlayer(
                figure: figure, idle: idle, now: Date().addingTimeInterval(-Double(index) * 0.6))
        }
    }

    /// The white panel under the buttons, as the design draws it.
    private static let panel = 144.0
    private static let lineupHeight = 96.0
    /// How far the squad stands into the panel.
    private static let standIn = 12.0
}
#endif
