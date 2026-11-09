#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SportsUI
import SwiftUI

/// 存成绩卡's page: `SavePictureSheet` on the live card, which changes with a tap, and under it the
/// first time 点数字和人物可以换, the backdrops the post has as thumbnails (its photos, its route, its
/// chart, then 纯色) and 小队名. Saved or shared, the card is drawn as it stands, at three pixels a
/// point.
struct ScoreCardSheet: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.locale) private var locale
    let model: ScoreCardModel
    let store: FeedStore
    let close: () -> Void

    var body: some View {
        SavePictureSheet(choices: AnyHashable(model.changes), picture: picture, close: close) {
            ScaledCard(model: model)
        } options: {
            VStack(alignment: .leading, spacing: Space.s) {
                if model.showsHint {
                    Text("点数字和人物可以换", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("scoreCard.hint")
                }
                if model.card.backdrops.count > 1 {
                    BackdropRow(model: model)
                }
                if model.squadName != nil {
                    SwitchRow(Text("小队名", bundle: .module), isOn: showsSquad, showsDivider: false)
                        .accessibilityIdentifier("scoreCard.showsSquad")
                }
            }
        }
        .accentTone(.brand)
        .haptic(.pick, trigger: model.changes)
        .task { await model.load(from: store) }
    }

    private var showsSquad: Binding<Bool> {
        Binding {
            model.card.showsSquad
        } set: {
            model.showSquad($0)
        }
    }

    /// The card as it stands, struck numbers left out, at 1080 × 1440 pixels.
    private func picture() -> UIImage? {
        let renderer = ImageRenderer(
            content: ScoreCardView(model: model, isSaving: true)
                .environment(\.sceneTheme, theme)
                .environment(\.locale, locale))
        renderer.scale = Self.pictureScale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    private static let pictureScale = 3.0
}

/// The card shrunk whole into the room the sheet gives it, still tappable.
private struct ScaledCard: View {
    let model: ScoreCardModel

    var body: some View {
        GeometryReader { proxy in
            let scale = min(
                proxy.size.width / ScoreCardModel.size.width, proxy.size.height / ScoreCardModel.size.height)
            ScoreCardView(model: model)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                    width: ScoreCardModel.size.width * scale, height: ScoreCardModel.size.height * scale,
                    alignment: .topLeading)
        }
        .aspectRatio(ScoreCardModel.size.width / ScoreCardModel.size.height, contentMode: .fit)
    }
}

/// The backdrops as 56-point thumbnails in a row; the picked one wears a graphite ring.
private struct BackdropRow: View {
    @Environment(\.sceneTheme) private var theme
    let model: ScoreCardModel

    private var colors: PostBlockColors { PostBlockColors(kind: .trained, activity: model.training.activity) }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.xs) {
                ForEach(Array(model.card.backdrops.enumerated()), id: \.offset) { index, backdrop in
                    Button {
                        model.pick(backdrop)
                    } label: {
                        thumbnail(backdrop)
                            .frame(width: Self.side, height: Self.side)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            .padding(Self.ringGap)
                            .overlay {
                                if backdrop == model.card.backdrop {
                                    RoundedRectangle(cornerRadius: Radius.card + Self.ringGap, style: .continuous)
                                        .strokeBorder(Color(role: .bgBrand, in: theme), lineWidth: Self.ring)
                                }
                            }
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel(label(of: backdrop, at: index))
                    .accessibilityAddTraits(backdrop == model.card.backdrop ? .isSelected : [])
                    .accessibilityIdentifier(identifier(of: backdrop, at: index))
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private func thumbnail(_ backdrop: ScoreCard.Backdrop) -> some View {
        switch backdrop {
        case .photo(let ref):
            if let photo = model.photos[ref] {
                Image(decorative: photo, scale: 1).resizable().scaledToFill()
            } else {
                Color(colors.shade)
            }
        case .map:
            if let map = model.map {
                Image(uiImage: map).resizable().scaledToFill()
            } else {
                Color(colors.shade)
            }
        case .chart:
            if let series = model.training.workout?.series {
                WorkoutChart(series: series, activity: model.training.activity).allowsHitTesting(false)
            } else {
                Color(colors.shade)
            }
        case .plain:
            Text("纯色", bundle: .module)
                .typeStyle(TypeRamp.label)
                .foregroundStyle(Color(colors.ink))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(colors.fill))
        }
    }

    private func label(of backdrop: ScoreCard.Backdrop, at index: Int) -> Text {
        switch backdrop {
        case .photo: Text("照片 \(index + 1)", bundle: .module)
        case .map: Text("路线", bundle: .module)
        case .chart: Text("图表", bundle: .module)
        case .plain: Text("纯色", bundle: .module)
        }
    }

    private func identifier(of backdrop: ScoreCard.Backdrop, at index: Int) -> String {
        switch backdrop {
        case .photo: "scoreCard.backdrop.photo.\(index)"
        case .map: "scoreCard.backdrop.map"
        case .chart: "scoreCard.backdrop.chart"
        case .plain: "scoreCard.backdrop.plain"
        }
    }

    private static let side: Double = 56
    private static let ringGap: Double = 3
    private static let ring: Double = 2
}
#endif
