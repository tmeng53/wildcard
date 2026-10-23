#if os(iOS)
import Contracts
import DailyPushDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The 6pm push, long-pressed: the squad's week and who patted the member on graphite, then
/// teammates' check-ins today on white, each with the 动态 reaction row. The emoji bar opens
/// over the post's smiley; ＋ lays every emoji over the push, since a push has no keyboard.
public struct DailyPushView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: DailyPushModel

    /// The view's own space, where the emoji bar and the flying emoji are placed.
    static let space = "dailyPush"

    public init(model: DailyPushModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            PushHeader(model: model)
            PushToday(model: model)
        }
        .background(Color(role: .bgCanvas, in: .gym))
        .overlay { EmojiBarLayer(model: model) }
        .overlay { FlightLayer(flight: model.flight, reduceMotion: reduceMotion) }
        .coordinateSpace(name: Self.space)
        // A push isn't in any squad's scene: it wears the brand.
        .environment(\.sceneTheme, .gym)
        .accentTone(.brand)
    }
}

/// The week so far on the brand's graphite, and who patted the member. Read-only; a tap opens 动态.
private struct PushHeader: View {
    let model: DailyPushModel

    private static let markSize: Double = 22
    private static let patHead: Double = 24
    private static let dot: Double = 8

    var body: some View {
        let week = model.push.squadWeek
        Button {
            model.go(.feed)
        } label: {
            VStack(alignment: .leading, spacing: Space.s - 2) {
                HStack(spacing: Space.xs) {
                    Image("AppMark", bundle: .module)
                        .resizable()
                        .frame(width: Self.markSize, height: Self.markSize)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail - 1, style: .continuous))
                        .accessibilityHidden(true)
                    Text("外卡", bundle: .module)
                        .typeStyle(TypeRamp.footnoteEmphasis)
                        .foregroundStyle(Color(role: .fgOnBrand, in: .gym))
                    Spacer(minLength: 0)
                    Text(model.arrived.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgSubtle, in: .gym))
                }
                HStack(alignment: .lastTextBaseline, spacing: Space.s - 2) {
                    Text("本周小队已练", bundle: .module)
                        .typeStyle(TypeRamp.calloutEmphasis)
                        .foregroundStyle(Color(role: .fgOnBrand, in: .gym))
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(verbatim: "\(week.trainedDays)")
                            .typeStyle(TypeRamp.scoreHero)
                        Text(verbatim: "/\(week.plannedDays)")
                            .typeStyle(TypeRamp.denominator(of: TypeRamp.scoreHero))
                            .opacity(0.5)
                    }
                    .foregroundStyle(Color(role: .fgOnBrand, in: .gym))
                    .monospacedDigit()
                    Text("次", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgSubtle, in: .gym))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    Text("本周小队已练 \(week.trainedDays)/\(week.plannedDays) 次", bundle: .module))
                Capsule()
                    .fill(Color(role: .fgOnBrand, in: .gym).opacity(0.2))
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color(role: .fgOnBrand, in: .gym))
                                .frame(width: proxy.size.width * fraction(week))
                        }
                    }
                    .frame(height: Sizing.progress)
                    .accessibilityHidden(true)
                if !model.push.pokedBy.isEmpty { pats }
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(role: .bgBrand, in: .gym))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("打开动态", bundle: .module))
    }

    private func fraction(_ week: WeekCount) -> Double {
        week.plannedDays > 0 ? min(Double(week.trainedDays) / Double(week.plannedDays), 1) : 0
    }

    /// Who patted the member: their heads, their names, and the volt dot a pat throws.
    private var pats: some View {
        let pokers = model.push.pokedBy
        return HStack(spacing: Space.xs) {
            HStack(spacing: -Space.xs + 2) {
                ForEach(pokers.prefix(3), id: \.self) { member in
                    Face(player: model.head(of: member), size: Self.patHead, ring: .bgBrand)
                }
            }
            Text("\(pokers.map(model.name(of:)).joined(separator: "、"))拍了拍你", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgOnBrand, in: .gym))
                .lineLimit(1)
            Circle()
                .fill(Color(role: .fgOnBrand, in: .gym))
                .frame(width: Self.dot, height: Self.dot)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Today's check-ins, or the squad standing and 我去发一个 when nobody has posted.
private struct PushToday: View {
    let model: DailyPushModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(Text("今天", bundle: .module))
                .padding(.top, Space.xxs)
                .padding(.bottom, Space.xxs)
            if model.push.nobodyPosted {
                EmptyDay(model: model)
            } else {
                ForEach(Array(model.push.posts.enumerated()), id: \.element.id) { index, post in
                    PostRow(model: model, post: post)
                        .overlay(alignment: .top) {
                            if index > 0 { Hairline() }
                        }
                }
                if model.push.more > 0 { more }
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.s - 2)
        .padding(.bottom, Space.xs - 2)
    }

    /// 「还有 n 条」: the rest are in 动态.
    private var more: some View {
        Button {
            model.go(.feed)
        } label: {
            HStack(spacing: Space.xxs) {
                Text("还有 \(model.push.more) 条，去动态看", bundle: .module)
                Image(systemName: "chevron.right")
                    .font(.system(size: Sizing.smallIcon - 3, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .typeStyle(TypeRamp.footnoteEmphasis)
            .foregroundStyle(Color(role: .fgMuted, in: .gym))
            .frame(maxWidth: .infinity, minHeight: Sizing.control)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .overlay(alignment: .top) { Hairline() }
        .padding(.horizontal, -Space.m)
        .accessibilityIdentifier("dailyPush.more")
    }
}

/// Nobody has posted today: the squad stands still, and the member can go first.
private struct EmptyDay: View {
    let model: DailyPushModel

    private static let figure = CGSize(width: 66, height: 92)

    var body: some View {
        VStack(spacing: Space.xxs) {
            HStack(spacing: 2) {
                ForEach(model.teammates, id: \.self) { member in
                    if let player = model.standing(member) {
                        Figure(player: player, moving: false)
                            .frame(width: Self.figure.width, height: Self.figure.height)
                    }
                }
            }
            .accessibilityHidden(true)
            Text("今天还没人发动态", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: .gym))
            Button {
                model.go(.checkIn)
            } label: {
                Text("我去发一个", bundle: .module)
            }
            .buttonStyle(PrimaryButtonStyle(.large))
            .padding(.top, Space.s - 2)
            .accessibilityIdentifier("dailyPush.checkIn")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.s + 2)
    }
}

/// A line between rows, edge to edge.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color(role: .borderDefault, in: .gym))
            .frame(height: Sizing.hairline)
            .accessibilityHidden(true)
    }
}
#endif
