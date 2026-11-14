#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import SportsUI
import SwiftUI

/// 小队菜单: up to three of the week's rated meals, the best 卡价比 first, as a menu to try, never a
/// ranking. Each is a photo card with its poster's head and 卡价比; a tap turns it over to its 健康
/// and 好吃 stars and the place, which opens 地点页 (approved 2026-11-12).
struct MenuPage: View {
    let dishes: [MenuDish]
    let page: PageContext
    /// Pushes 地点页 over the story.
    let openPlace: (Place) -> Void
    /// The reader turned a card: the page stays up until they tap on.
    let stay: () -> Void
    @Environment(\.sceneTheme) private var theme
    /// Each poster's head, made once as the page appears (not in `init`: the page is made anew on
    /// every frame of its clock).
    @State private var heads: [MemberID: CharacterPlayer] = [:]
    @State private var showsInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            PageTitle(label: Text(copy: "本周", bundle: .module), title: Text(copy: "小队菜单", bundle: .module))
            VStack(alignment: .trailing, spacing: Space.xs) {
                info
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)],
                    alignment: .leading, spacing: Space.m
                ) {
                    ForEach(Array(dishes.enumerated()), id: \.element.checkIn) { index, dish in
                        MenuCard(
                            dish: dish, nickname: page.cast.nickname(of: dish.author), head: heads[dish.author],
                            chipShown: page.pop(0.45 + Double(index) * 0.09, 0.87 + Double(index) * 0.09),
                            openPlace: openPlace, stay: stay
                        )
                        .opacity(page.ramp(0.15 + Double(index) * 0.09, 0.4 + Double(index) * 0.09))
                        .offset(y: 18 * (1 - page.pop(0.15 + Double(index) * 0.09, 0.71 + Double(index) * 0.09)))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("recap.menu.\(index)")
                    }
                }
            }
            .padding(.horizontal, Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: makeHeads)
        .onChange(of: dishes, makeHeads)
    }

    /// 「卡价比 ⓘ」, whose tap says what it is and nothing more.
    private var info: some View {
        Button {
            showsInfo = true
            stay()
        } label: {
            HStack(spacing: Space.xxs) {
                Text(copy: "卡价比", bundle: .module)
                Image(systemName: "info.circle").accessibilityHidden(true)
            }
            .typeStyle(TypeRamp.caption)
            .foregroundStyle(Color(role: .fgOnScene, in: theme))
            .frame(minHeight: Sizing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recap.menu.info")
        .popover(isPresented: $showsInfo) {
            Text(copy: "卡路里性价比", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func makeHeads() {
        heads = Dictionary(
            dishes.compactMap { dish in page.cast.player(of: dish.author).map { (dish.author, $0) } },
            uniquingKeysWith: { first, _ in first })
    }
}

/// One dish: the photo with its poster's head and 卡价比 on the front; 健康, 好吃 and the place on
/// the back. A tap anywhere but the place turns it over.
private struct MenuCard: View {
    let dish: MenuDish
    let nickname: String
    let head: CharacterPlayer?
    /// How far the 卡价比 chip has popped in, 0 to 1 and a little over.
    let chipShown: Double
    let openPlace: (Place) -> Void
    let stay: () -> Void
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsBack = false
    /// How far the card has turned on its vertical axis: edge-on, sides swapped out of sight, back.
    @State private var turn: Double = 0
    @State private var isTurning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if showsBack { back } else { front }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .onTapGesture(perform: flip)
            .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: Text(copy: "轻点翻面", bundle: .module), flip)
            if let name = dish.name {
                Text(verbatim: name)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .lineLimit(1)
                    .padding(.top, Space.xs)
            }
            Text(verbatim: nickname)
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .fgOnScene, in: theme).opacity(0.7))
                .lineLimit(1)
                .padding(.top, Space.xxs / 2)
        }
        .foregroundStyle(Color(role: .fgOnScene, in: theme))
    }

    private var front: some View {
        ZStack(alignment: .top) {
            photo
            HStack(alignment: .top) {
                MemberHead(player: head, size: Sizing.characterHead)
                Spacer(minLength: Space.xs)
                Text(verbatim: dish.calorieValueText)
                    .typeStyle(TypeRamp.scoreSmall)
                    .foregroundStyle(Color(role: .fgAccent, in: theme))
                    .padding(.horizontal, Space.xs)
                    .frame(height: Sizing.tag - 2)
                    .background(Color(role: .bgCanvas, in: theme), in: Capsule())
                    .scaleEffect(max(chipShown, 0.01))
                    .opacity(min(max(chipShown, 0), 1))
                    .accessibilityLabel(Text(copy: "卡价比 \(dish.calorieValueText)", bundle: .module))
            }
            .padding(Space.xs)
        }
    }

    @ViewBuilder
    private var photo: some View {
        if let url = dish.photo {
            Color(role: .bgSubtle, in: theme)
                .overlay {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color(role: .bgSubtle, in: theme)
                    }
                }
                .clipped()
                .accessibilityLabel(Text(copy: "照片", bundle: .module))
        } else {
            // The meal's colour alone: its words are the name under the card, and a tile's corner
            // label would sit under the 卡价比 chip.
            PostBlock(kind: .healthyMeal, layout: .thumbnail)
        }
    }

    private var back: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            stars(Text(copy: "健康", bundle: .module), dish.healthy)
            stars(Text(copy: "好吃", bundle: .module), dish.tasty)
                .padding(.top, Space.xs)
            Spacer(minLength: Space.xs)
            if let place = dish.place {
                Button {
                    openPlace(place)
                } label: {
                    HStack(spacing: Space.xxs) {
                        Text(verbatim: place.name).lineLimit(1)
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .frame(minHeight: Sizing.minimumTapTarget, alignment: .bottomLeading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recap.menu.place")
            }
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(role: .bgCanvas, in: theme))
    }

    private func stars(_ label: Text, _ rating: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            label
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
            StarRating(rating: rating, size: 18, spacing: Space.xxs / 2)
        }
        .accessibilityElement(children: .combine)
    }

    /// Half a turn each way on the page spring's time, as the player card turns; the story stays
    /// on the page once the reader plays with it.
    private func flip() {
        stay()
        guard !isTurning else { return }
        if reduceMotion {
            withAnimation(.wildcard(Motion.page, reduceMotion: true)) { showsBack.toggle() }
            return
        }
        isTurning = true
        let half = Motion.page.response / 2
        withAnimation(.easeIn(duration: half)) {
            turn = 90
        } completion: {
            showsBack.toggle()
            turn = -90
            withAnimation(.easeOut(duration: half)) {
                turn = 0
            } completion: {
                isTurning = false
            }
        }
    }
}
#endif
