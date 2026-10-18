#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

// MARK: - Color

struct ColorSection: View {
    private let neutrals: [(role: ColorRole, name: Text)] = [
        (.canvas, Text("画布", bundle: .module)),
        (.surface, Text("表面", bundle: .module)),
        (.divider, Text("线", bundle: .module)),
        (.textPrimary, Text("正文", bundle: .module)),
        (.textSecondary, Text("次要", bundle: .module)),
        (.textTertiary, Text("第三级", bundle: .module)),
    ]

    private let signature: [(role: ColorRole, name: Text)] = [
        (.signature, Text("签名", bundle: .module)),
        (.signatureShade, Text("深一档", bundle: .module)),
        (.signatureWash, Text("浅底", bundle: .module)),
        (.onSignature, Text("签名上的字", bundle: .module)),
        (.signatureText, Text("签名色文字", bundle: .module)),
        (.progressFill, Text("进度", bundle: .module)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle(number: 1, title: Text("配色", bundle: .module))
            SwatchGroup(title: Text("中性色", bundle: .module), swatches: neutrals)
            SwatchGroup(title: Text("场景签名色", bundle: .module), swatches: signature)
            VStack(alignment: .leading, spacing: Space.s) {
                GroupTitle(title: Text("含义色", bundle: .module))
                MeaningTags()
            }
        }
    }
}

private struct GroupTitle: View {
    @Environment(\.sceneTheme) private var theme
    let title: Text

    var body: some View {
        title
            .typeStyle(TypeRamp.headline)
            .foregroundStyle(Color(role: .textSecondary, in: theme))
    }
}

private struct SwatchGroup: View {
    let title: Text
    let swatches: [(role: ColorRole, name: Text)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            GroupTitle(title: title)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3),
                spacing: Space.xs
            ) {
                ForEach(swatches, id: \.role) { swatch in
                    Swatch(role: swatch.role, name: swatch.name)
                }
            }
        }
    }
}

private struct Swatch: View {
    @Environment(\.sceneTheme) private var theme
    let role: ColorRole
    let name: Text

    var body: some View {
        let fill = role.color(in: theme)
        let ink = ColorRole.textPrimary.color(in: theme)
        let paper = ColorRole.canvas.color(in: theme)
        let label = fill.contrastRatio(with: ink) >= fill.contrastRatio(with: paper) ? ink : paper
        VStack(alignment: .leading, spacing: Space.xxs) {
            Spacer(minLength: 0)
            name
                .typeStyle(TypeRamp.caption)
            Text(verbatim: fill.hex)
                .typeStyle(TypeRamp.scoreLabel)
        }
        .foregroundStyle(Color(label))
        .padding(Space.s)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .background(Color(fill), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .strokeBorder(Color(role: .divider, in: theme), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Meaning colors are accents only: a dot, an icon and a tag (wash with dark text).
private struct MeaningTags: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(Meaning.allCases, id: \.self) { meaning in
                HStack(spacing: Space.s) {
                    Circle()
                        .fill(Color(role: meaning.tint, in: theme))
                        .frame(width: Space.xs, height: Space.xs)
                    HStack(spacing: Space.xxs) {
                        Image(systemName: meaning.symbol)
                            .foregroundStyle(Color(role: meaning.ink, in: theme))
                            .accessibilityHidden(true)
                        meaning.fullName
                            .foregroundStyle(Color(role: meaning.text, in: theme))
                    }
                    .typeStyle(TypeRamp.caption)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xxs + Space.xxs / 2)
                    .background(Color(role: meaning.wash, in: theme), in: Capsule())
                    Spacer(minLength: 0)
                    Text(verbatim: meaning.accent(in: theme).tint.hex)
                        .typeStyle(TypeRamp.scoreLabel)
                        .foregroundStyle(Color(role: .textSecondary, in: theme))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Type

struct TypeSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle(number: 2, title: Text("字体", bundle: .module))
            VStack(alignment: .leading, spacing: Space.l) {
                Sample(token: "hero", style: TypeRamp.hero, text: Text("名场面", bundle: .module))
                Sample(token: "title", style: TypeRamp.title, text: Text("出赛表", bundle: .module))
                Sample(token: "headline", style: TypeRamp.headline, text: Text("周三不练腿俱乐部", bundle: .module))
                Sample(token: "body", style: TypeRamp.body, text: Text("练腿日，腿还在", bundle: .module))
                Sample(
                    token: "callout", style: TypeRamp.callout,
                    text: Text("会开到第五个，我已经分不清自己是人还是待办", bundle: .module))
                Sample(token: "caption", style: TypeRamp.caption, text: Text("今天 3 人练了", bundle: .module))
                Sample(token: "footnote", style: TypeRamp.footnote, text: Text("我 · 本周", bundle: .module))
                ScoreSamples()
            }
        }
    }
}

private struct ScoreSamples: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .lastTextBaseline, spacing: Space.l) {
                Sample(token: "scoreHero", style: TypeRamp.scoreHero, text: Text(verbatim: "90"))
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Score(
                        count: 18, goal: 25, countStyle: TypeRamp.scoreLarge,
                        goalStyle: TypeRamp.scoreLargeDenominator)
                    TokenLabel(text: "scoreLarge · 52 / 28")
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: Space.l) {
                Sample(token: "scoreMedium", style: TypeRamp.scoreMedium, text: Text(verbatim: "12"))
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Score(
                        count: 3, goal: 5, countStyle: TypeRamp.scoreSmall, goalStyle: TypeRamp.scoreSmallDenominator)
                    TokenLabel(text: "scoreSmall · 20 / 14")
                }
            }
            Sample(token: "scoreLabel", style: TypeRamp.scoreLabel, text: Text(verbatim: "WK42 · LANE 3"))
        }
    }
}

private struct Sample: View {
    @Environment(\.sceneTheme) private var theme
    let token: String
    let style: TypeStyle
    let text: Text

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            text
                .typeStyle(style)
                .foregroundStyle(Color(role: .textPrimary, in: theme))
            TokenLabel(text: "\(token) · \(Int(style.size))")
        }
    }
}

/// The token's code name: for developers, so it is not translated.
private struct TokenLabel: View {
    @Environment(\.sceneTheme) private var theme
    let text: String

    var body: some View {
        Text(verbatim: text)
            .typeStyle(TypeRamp.scoreLabel)
            .foregroundStyle(Color(role: .textSecondary, in: theme))
    }
}

// MARK: - Motion

struct MotionSection: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var atFinish = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle(number: 3, title: Text("动效", bundle: .module))
            VStack(spacing: 0) {
                ForEach(Motion.all.indices, id: \.self) { index in
                    let runner = Motion.all[index]
                    Lane(number: index + 1, name: runner.name, atFinish: atFinish)
                        .animation(
                            .wildcard(runner.spring, reduceMotion: reduceMotion)
                                .delay(Motion.stagger * Double(index)),
                            value: atFinish
                        )
                }
                Rectangle().fill(Color(role: .divider, in: theme)).frame(height: 1)
            }
            Button {
                atFinish.toggle()
            } label: {
                (atFinish ? Text("回到起点", bundle: .module) : Text("开跑", bundle: .module))
                    .typeStyle(TypeRamp.action)
                    .padding(.horizontal, Space.xl)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("styleguide.motion.play")
        }
    }
}

private struct Lane: View {
    @Environment(\.sceneTheme) private var theme
    let number: Int
    let name: String
    let atFinish: Bool

    private let runnerSize: Double = 24

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(role: .divider, in: theme)).frame(height: 1)
            HStack(spacing: Space.s) {
                Text(verbatim: "\(number)")
                    .typeStyle(TypeRamp.scoreSmall)
                    .foregroundStyle(Color(role: .textTertiary, in: theme))
                    .frame(width: 20)
                GeometryReader { proxy in
                    Circle()
                        .fill(Color(role: .signature, in: theme))
                        .frame(width: runnerSize, height: runnerSize)
                        .offset(x: atFinish ? proxy.size.width - runnerSize : 0)
                        .frame(maxHeight: .infinity)
                }
                Text(verbatim: name.uppercased())
                    .typeStyle(TypeRamp.scoreLabel)
                    .foregroundStyle(Color(role: .textSecondary, in: theme))
                    .frame(width: 64, alignment: .trailing)
            }
            .frame(height: 48)
        }
        .accessibilityHidden(true)
    }
}
#endif
