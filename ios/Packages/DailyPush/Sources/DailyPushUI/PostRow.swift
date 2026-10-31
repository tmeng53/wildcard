#if os(iOS)
import AvatarUI
import Contracts
import DailyPushDomain
import FeedDomain
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// One teammate's check-in: their character at the left, holding still until someone reacts,
/// their name and time, the kind's tag and one line of words, then the reaction row (style B):
/// heads wearing their emoji, newest first, four then 「+n」, and my smiley at the right.
struct PostRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: DailyPushModel
    let post: PushPost

    private static let figureColumn: Double = 60
    private static let figure = CGSize(width: 64, height: 89)
    private static let rowHeads = 4
    private static let mineStroke: Double = 1.5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.s - 2) {
                character
                    .frame(width: Self.figureColumn, height: Sizing.characterBust, alignment: .topLeading)
                details
            }
            reactions
                .padding(.leading, Self.figureColumn + Space.s - 2)
        }
        .padding(.top, Space.xs)
        .padding(.bottom, Space.xs - 2)
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            ForEach(Emoji.quick, id: \.self) { emoji in
                Button {
                    model.pick(emoji, on: post.id, from: .zero)
                } label: {
                    Text("回应 \(emoji.text)", bundle: .module)
                }
            }
        }
        .accessibilityIdentifier("dailyPush.post")
    }

    // MARK: - The character

    private var character: some View {
        let played = model.played[post.id]
        let bubble = model.bubbles[post.id]
        return ZStack(alignment: .top) {
            if let player = model.player(for: post) {
                Figure(player: player, moving: played != nil && !reduceMotion)
                    .frame(width: Self.figure.width, height: Self.figure.height)
                    .offset(x: -4, y: -2)
                    .task(id: played?.count) {
                        guard let played else { return }
                        try? await Task.sleep(for: .seconds(max(played.until.timeIntervalSinceNow, 0)))
                        model.finished(post.id, count: played.count)
                    }
            }
            if let bubble {
                SpeechBubble(Text(verbatim: bubble.emoji.text), on: .page)
                    .fixedSize()
                    .offset(y: -Space.l + 2)
                    .transition(.speech(reduceMotion: reduceMotion))
                    .task(id: bubble.count) {
                        try? await Task.sleep(for: .seconds(DailyPushModel.bubbleTime))
                        withAnimation(.wildcard(Motion.sheet.exit, reduceMotion: reduceMotion)) {
                            model.bubbleDone(post.id, count: bubble.count)
                        }
                    }
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: bubble?.count)
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(DailyPushView.space))
        } action: { frame in
            model.figures[post.id] = frame
        }
        .accessibilityHidden(true)
    }

    // MARK: - Who, when, what

    private var details: some View {
        VStack(alignment: .leading, spacing: Space.xxs + 1) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs - 2) {
                Text(verbatim: model.name(of: post.author))
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: .gym))
                    .lineLimit(1)
                Text(post.posted.date, format: .dateTime.hour().minute())
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: .gym))
                    .lineLimit(1)
            }
            kindTag
            if let text = post.text {
                Text(verbatim: text)
                    .typeStyle(post.entry == .disclaimer ? TypeRamp.calloutEmphasis : TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgDefault, in: .gym))
                    .lineLimit(post.entry == .disclaimer ? 2 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var kindTag: some View {
        switch post.entry {
        case .trained(let activity?):
            Tag(Text("练了 · \(activity.name)", bundle: .module))
        case .trained(nil):
            Tag(Text("练了", bundle: .module))
        case .healthyMeal:
            Tag(Text("健康餐", bundle: .module))
        case .cheatMeal:
            Tag(Text("坦白放纵餐", bundle: .module))
        case .disclaimer:
            LeaveTag()
        }
    }

    // MARK: - The reaction row

    private var reactions: some View {
        let latest = post.latest(Self.rowHeads)
        let extra = post.reactionCount - latest.count
        let mine = post.reactions.kind(of: model.push.viewer)
        return HStack(spacing: Space.xs - 2) {
            if !latest.isEmpty {
                HStack(spacing: Space.xxs) {
                    ForEach(latest, id: \.member) { response in
                        Face(player: model.head(of: response.member), size: Sizing.characterHead - 2, ring: nil)
                            .overlay(alignment: .bottomTrailing) {
                                Text(verbatim: response.kind.text)
                                    .font(.system(size: 12))
                                    .offset(x: 5, y: 4)
                            }
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary)
                if extra > 0 {
                    Text(verbatim: "+\(extra)")
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: .gym))
                }
            }
            Spacer(minLength: 0)
            myButton(mine)
        }
        .frame(minHeight: Sizing.compactControl)
        .animation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion), value: latest.map(\.member))
    }

    /// 「3 人回应：💪 2，😂 1」
    private var summary: Text {
        let groups = post.reactions.groups.map { "\($0.kind.text) \($0.members.count)" }.joined(separator: "，")
        return Text("\(post.reactionCount) 人回应：\(groups)", bundle: .module)
    }

    private func myButton(_ mine: Emoji?) -> some View {
        Button {
            withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { model.picking = post.id }
        } label: {
            Group {
                if let mine {
                    Text(verbatim: mine.text).font(.system(size: Sizing.icon))
                } else {
                    Image(systemName: "face.smiling")
                        .font(.system(size: Sizing.icon, weight: .regular))
                        .foregroundStyle(Color(role: .fgMuted, in: .gym))
                }
            }
            .frame(width: Sizing.minimumTapTarget, height: Sizing.compactControl - 2)
            .background(Color(role: mine == nil ? .bgSubtle : .bgCanvas, in: .gym), in: Capsule())
            // Once I reacted, white with a dark outline, as on 动态 (a brand screen: no scene colour).
            .overlay {
                if mine != nil {
                    Capsule().strokeBorder(Color(role: .fgDefault, in: .gym), lineWidth: Self.mineStroke)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(DailyPushView.space))
        } action: { frame in
            model.buttons[post.id] = frame
        }
        .accessibilityLabel(
            mine.map { Text("我的回应 \($0.text)，换一个", bundle: .module) } ?? Text("回应", bundle: .module)
        )
        .accessibilityIdentifier("dailyPush.react")
    }
}

/// 请假条's tag: grey, with the moon.
private struct LeaveTag: View {
    var body: some View {
        HStack(spacing: Space.xxs) {
            Image(systemName: "moon.fill")
                .font(.system(size: Sizing.smallIcon - 3, weight: .semibold))
                .accessibilityHidden(true)
            Text("请假条", bundle: .module)
                .typeStyle(TypeRamp.footnoteEmphasis)
                .lineLimit(1)
        }
        .foregroundStyle(Color(role: .fgMuted, in: .gym))
        .padding(.horizontal, Space.s)
        .frame(minHeight: Sizing.tag)
        .background(Color(role: .borderDefault, in: .gym), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A member's head in a small circle, as in 动态's row.
struct Face: View {
    let player: CharacterPlayer?
    let size: Double
    /// A ring in this colour, for heads that overlap.
    let ring: ColorRole?

    var body: some View {
        Circle()
            .fill(Color(role: .bgSubtle, in: .gym))
            .overlay {
                if let player { CharacterHead(player: player).clipShape(Circle()) }
            }
            .overlay {
                if let ring { Circle().stroke(Color(role: ring, in: .gym), lineWidth: Sizing.ringGap) }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A character standing: drawn once while still, every frame only while a move plays.
struct Figure: View {
    let player: CharacterPlayer
    let moving: Bool

    var body: some View {
        if moving {
            CharacterView(player: player)
        } else {
            let frame = player.restFrame
            CharacterCanvas(drawing: frame.drawing, placements: frame.placements)
                .aspectRatio(frame.drawing.width / frame.drawing.height, contentMode: .fit)
        }
    }
}
#endif
