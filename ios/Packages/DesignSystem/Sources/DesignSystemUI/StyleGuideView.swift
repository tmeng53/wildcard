#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Every token on one screen: the app shows it until the first feature screen lands, and CI
/// screenshots it so a change to a token is visible in review.
public struct StyleGuideView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScoreHeader()
                VStack(alignment: .leading, spacing: Space.xxl) {
                    PaletteSection()
                    TypeSection()
                    MotionSection()
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xxl)
            }
        }
        .background {
            // Sky behind the status bar and the top overscroll, canvas below.
            VStack(spacing: 0) {
                Color(role: .skyWash).frame(height: 400)
                Color(role: .canvas)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Header

/// A broadcast score under a sunny sky, over a strip of track.
private struct ScoreHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(verbatim: "WK42 · DESIGN SYSTEM")
                    .typeStyle(TypeRamp.scoreLabel)
                    .foregroundStyle(Color(role: .sky))
                HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                    Text(verbatim: "18")
                        .foregroundStyle(Color(role: .textPrimary))
                    Text(verbatim: "/25")
                        .foregroundStyle(Color(role: .textSecondary))
                }
                .typeStyle(TypeRamp.scoreHero)
                Text("小队本周打卡", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .textSecondary))
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.l)
            .padding(.bottom, Space.l)
            TrackStrip(lanes: 4)
                .frame(height: 64)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(role: .skyWash))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("styleguide.header")
    }
}

/// Track-red lanes with white lines and lane numbers.
private struct TrackStrip: View {
    let lanes: Int

    var body: some View {
        GeometryReader { proxy in
            let laneHeight = proxy.size.height / Double(lanes)
            ZStack(alignment: .topLeading) {
                Color(role: .brand)
                ForEach(0..<lanes, id: \.self) { lane in
                    Rectangle()
                        .fill(Color(role: .textOnFill).opacity(0.85))
                        .frame(height: 1.5)
                        .offset(y: laneHeight * Double(lane))
                    Text(verbatim: "\(lane + 1)")
                        .typeStyle(TypeRamp.scoreLabel)
                        .foregroundStyle(Color(role: .textOnFill))
                        .frame(width: 28, height: laneHeight)
                        .offset(x: Space.gutter - Space.xs, y: laneHeight * Double(lane))
                }
                Rectangle()
                    .fill(Color(role: .textOnFill))
                    .frame(width: 4)
                    .offset(x: proxy.size.width * 0.72)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Palette

private struct PaletteSection: View {
    private let swatches: [(role: ColorRole, name: Text)] = [
        (.textPrimary, Text("墨蓝", bundle: .module)),
        (.brand, Text("跑道红", bundle: .module)),
        (.sky, Text("转播蓝", bundle: .module)),
        (.achievement, Text("奖牌金", bundle: .module)),
        (.fresh, Text("草地绿", bundle: .module)),
        (.skyWash, Text("晴空", bundle: .module)),
        (.surface, Text("粉笔白", bundle: .module)),
        (.textSecondary, Text("次要文字", bundle: .module)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle(number: 1, title: Text("配色", bundle: .module))
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)],
                spacing: Space.s
            ) {
                ForEach(swatches, id: \.role) { swatch in
                    Swatch(role: swatch.role, name: swatch.name)
                }
            }
        }
    }
}

private struct Swatch: View {
    let role: ColorRole
    let name: Text

    var body: some View {
        let fill = role.color
        let label =
            fill.contrastRatio(with: Palette.ink) >= fill.contrastRatio(with: Palette.white)
            ? Color(Palette.ink) : Color(Palette.white)
        VStack(alignment: .leading, spacing: Space.xxs) {
            Spacer(minLength: 0)
            name
                .typeStyle(TypeRamp.headline)
            Text(verbatim: fill.hex)
                .typeStyle(TypeRamp.scoreLabel)
                .opacity(0.75)
        }
        .foregroundStyle(label)
        .padding(Space.m)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Color(fill), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .strokeBorder(Color(role: .divider), lineWidth: fill == Palette.chalk ? 1 : 0)
        }
    }
}

// MARK: - Type

private struct TypeSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle(number: 2, title: Text("字体", bundle: .module))
            VStack(alignment: .leading, spacing: Space.l) {
                Sample(token: "hero", style: TypeRamp.hero, text: Text("今天你练了吗", bundle: .module))
                Sample(token: "title", style: TypeRamp.title, text: Text("周日战报", bundle: .module))
                Sample(token: "headline", style: TypeRamp.headline, text: Text("练了 · 吃得干净 · Coco", bundle: .module))
                Sample(token: "body", style: TypeRamp.body, text: Text("今日免责声明：下雨了，跑步机也湿了。", bundle: .module))
                Sample(token: "caption", style: TypeRamp.caption, text: Text("三个队友都练了，就差你", bundle: .module))
                HStack(alignment: .lastTextBaseline, spacing: Space.l) {
                    Sample(token: "scoreLarge", style: TypeRamp.scoreLarge, text: Text(verbatim: "90'"))
                    Sample(token: "scoreMedium", style: TypeRamp.scoreMedium, text: Text(verbatim: "4/3"))
                    Sample(token: "scoreLabel", style: TypeRamp.scoreLabel, text: Text(verbatim: "LANE 3"))
                }
            }
        }
    }
}

private struct Sample: View {
    let token: String
    let style: TypeStyle
    let text: Text

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            text
                .typeStyle(style)
                .foregroundStyle(Color(role: .textPrimary))
            Text(verbatim: "\(token) · \(Int(style.size))")
                .typeStyle(TypeRamp.scoreLabel)
                .foregroundStyle(Color(role: .textSecondary))
        }
    }
}

// MARK: - Motion

private struct MotionSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var atFinish = false

    private struct Runner {
        let name: String
        let spring: MotionSpring
        let color: ColorRole
    }

    private let runners = [
        Runner(name: "snappy", spring: Motion.snappy, color: .sky),
        Runner(name: "bouncy", spring: Motion.bouncy, color: .brand),
        Runner(name: "smooth", spring: Motion.smooth, color: .achievement),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle(number: 3, title: Text("动效", bundle: .module))
            VStack(spacing: 0) {
                ForEach(runners.indices, id: \.self) { index in
                    let runner = runners[index]
                    Lane(number: index + 1, name: runner.name, color: runner.color, atFinish: atFinish)
                        .animation(
                            .wildcard(runner.spring, reduceMotion: reduceMotion)
                                .delay(Motion.stagger * Double(index)),
                            value: atFinish
                        )
                }
                Rectangle().fill(Color(role: .divider)).frame(height: 1)
            }
            Button {
                atFinish.toggle()
            } label: {
                (atFinish ? Text("回到起点", bundle: .module) : Text("开跑", bundle: .module))
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .textOnFill))
                    .padding(.horizontal, Space.xl)
                    .padding(.vertical, Space.s + Space.xxs)
                    .background(Color(role: .brand), in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("styleguide.motion.play")
        }
    }
}

private struct Lane: View {
    let number: Int
    let name: String
    let color: ColorRole
    let atFinish: Bool

    private let runnerSize: Double = 28

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(role: .divider)).frame(height: 1)
            HStack(spacing: Space.s) {
                Text(verbatim: "\(number)")
                    .typeStyle(TypeRamp.scoreMedium)
                    .foregroundStyle(Color(role: .textSecondary))
                    .frame(width: 20)
                GeometryReader { proxy in
                    Circle()
                        .fill(Color(role: color))
                        .frame(width: runnerSize, height: runnerSize)
                        .offset(x: atFinish ? proxy.size.width - runnerSize : 0)
                        .frame(maxHeight: .infinity)
                }
                Text(verbatim: name.uppercased())
                    .typeStyle(TypeRamp.scoreLabel)
                    .foregroundStyle(Color(role: .textSecondary))
                    .frame(width: 64, alignment: .trailing)
            }
            .frame(height: 56)
        }
    }
}

// MARK: - Shared

private struct SectionTitle: View {
    let number: Int
    let title: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(verbatim: String(format: "%02d", number))
                .typeStyle(TypeRamp.scoreMedium)
                .foregroundStyle(Color(role: .brand))
            title
                .typeStyle(TypeRamp.title)
                .foregroundStyle(Color(role: .textPrimary))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    StyleGuideView()
}
#endif
