#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import FeedUI
import PlacesDomain
import SportsUI
import SwiftUI

/// The squad's posts at the place, pictures first like a map's reviews (Tracy, 2026-11-12): two
/// columns of square tiles, the newest first, each the same post tile as 我的动态's with a small
/// score at its foot and who posted it on which day under it. A tap opens the post.
struct VisitGrid: View {
    let store: PlacePageStore
    let today: LocalDay
    let openPost: (CheckInID) -> Void
    @State private var heads = AuthorHeads()

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Space.s - 2), GridItem(.flexible(), spacing: Space.s - 2)],
            alignment: .leading, spacing: Space.m - 2
        ) {
            ForEach(store.posts) { visit in
                Button {
                    openPost(visit.id)
                } label: {
                    VisitTile(
                        store: store, visit: visit, author: store.characters[visit.author],
                        head: heads.player(for: store.characters[visit.author]?.look),
                        day: DayHeading(visit.day, today: today))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("place.post")
            }
        }
    }
}

/// One post at the place: its cover photo or its colour with its sport's icons (the shared
/// `PostBlock` tile), and the author's head, name and day under it.
private struct VisitTile: View {
    let store: PlacePageStore
    let visit: PlaceVisit
    let author: MemberCharacter?
    let head: CharacterPlayer?
    let day: DayHeading
    @State private var cover: CGImage?
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            PostBlock(
                kind: visit.kind, activity: visit.activity, minutes: visit.minutes,
                photo: cover.map { Image(decorative: $0, scale: 1) }, layout: .tile
            )
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            HStack(spacing: Space.xs - 2) {
                MemberHead(player: head, size: 20)
                Text(verbatim: author?.nickname.text ?? String(copy: "队友", bundle: .module))
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                Spacer(minLength: Space.xxs)
                day.title
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .task(id: visit.cover?.path) {
            guard let ref = visit.cover else {
                cover = nil
                return
            }
            guard let jpeg = await store.photo(ref) else { return }
            cover = await CoverThumbnail.make(jpeg)
        }
    }
}

/// The authors' heads, made once a look: a character player is too costly to make each frame.
@MainActor
private final class AuthorHeads {
    private var players: [CharacterLook: CharacterPlayer] = [:]

    func player(for look: CharacterLook?) -> CharacterPlayer? {
        let look = look ?? CharacterLook(outfit: PlaceholderCharacter.lifter, persona: .energetic)
        if let player = players[look] { return player }
        guard let figure = try? PlaceholderCharacter.figure(wearing: Outfit(look)),
            let player = try? CharacterPlayer(figure: figure, idle: .still)
        else { return nil }
        players[look] = player
        return player
    }
}
#endif
