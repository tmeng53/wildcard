#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The choice components in a small multi-select sport picker: search, recent pills, the
/// category bar, a grid of tiles and the primary 完成 button. Sample data only; the real
/// picker lives in a feature package.
struct ChoiceSection: View {
    @Environment(\.sceneTheme) private var theme
    @State private var query = ""
    @State private var category = SampleCategory.runWalk
    @State private var picked: Set<SampleSport> = [.run]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle(number: 4, title: Text("选择", bundle: .module))
            VStack(alignment: .leading, spacing: Space.m) {
                SearchField(text: $query, prompt: Text("搜索运动", bundle: .module))
                    .padding(.horizontal, Space.m)
                    .accessibilityIdentifier("styleguide.picker.search")
                VStack(alignment: .leading, spacing: Space.xxs) {
                    SectionLabel(Text("最近使用", bundle: .module))
                        .padding(.horizontal, Space.m)
                    ScrollView(.horizontal) {
                        HStack(spacing: Sizing.pillGap) {
                            ForEach(SampleSport.recent, id: \.self) { sport in
                                ChoicePill(sport.name, systemImage: sport.symbol, isSelected: picked.contains(sport)) {
                                    toggle(sport)
                                }
                                .accessibilityIdentifier("styleguide.picker.pill.\(sport.rawValue)")
                            }
                        }
                        .padding(.horizontal, Space.m)
                    }
                    .scrollIndicators(.hidden)
                    .horizontalScrollFade()
                }
                VStack(alignment: .leading, spacing: Space.xxs) {
                    SectionLabel(Text("全部运动", bundle: .module))
                        .padding(.horizontal, Space.m)
                    CategoryBar(categories, selection: $category)
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3),
                    spacing: Space.xs
                ) {
                    ForEach(category.sports, id: \.self) { sport in
                        ChoiceTile(sport.name, systemImage: sport.symbol, isSelected: picked.contains(sport)) {
                            toggle(sport)
                        }
                        .accessibilityIdentifier("styleguide.picker.tile.\(sport.rawValue)")
                    }
                }
                .padding(.horizontal, Space.m)
                DoneButton(count: picked.count)
                    .padding(.horizontal, Space.m)
            }
            .padding(.vertical, Space.m)
            // The calm page a picker sits on: a quiet light surface, so the white tiles read.
            .background(
                Color(role: .surface, in: theme),
                in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            )
        }
    }

    private var categories: [CategoryBarItem<SampleCategory>] {
        SampleCategory.allCases.map { category in
            CategoryBarItem(
                id: category, title: category.name,
                accessibilityIdentifier: "styleguide.picker.category.\(category.rawValue)")
        }
    }

    private func toggle(_ sport: SampleSport) {
        if picked.contains(sport) {
            picked.remove(sport)
        } else {
            picked.insert(sport)
        }
    }
}

/// 完成 · N: the primary button, with the count in the scoreboard face.
private struct DoneButton: View {
    let count: Int

    var body: some View {
        Button {
            // The style guide has nowhere to go; a feature screen closes the picker here.
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text("完成", bundle: .module)
                    .typeStyle(TypeRamp.action)
                Text(verbatim: "·")
                    .typeStyle(TypeRamp.action)
                Text(verbatim: "\(count)")
                    .typeStyle(TypeRamp.scoreSmall)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(count == 0)
        .accessibilityIdentifier("styleguide.picker.done")
    }
}

// MARK: - Sample data

private enum SampleCategory: String, CaseIterable, Hashable {
    case runWalk, strength, cardio, mindBody, water, racket, ball

    var name: Text {
        switch self {
        case .runWalk: Text("跑走", bundle: .module)
        case .strength: Text("力量", bundle: .module)
        case .cardio: Text("有氧", bundle: .module)
        case .mindBody: Text("身心", bundle: .module)
        case .water: Text("水上", bundle: .module)
        case .racket: Text("球拍", bundle: .module)
        case .ball: Text("球类", bundle: .module)
        }
    }

    var sports: [SampleSport] {
        switch self {
        case .runWalk: [.run, .walk, .hike, .trailRun]
        case .strength: [.strength]
        case .cardio: [.jumpRope]
        case .mindBody: [.yoga]
        case .water: [.swim]
        case .racket: [.tennis]
        case .ball: [.basketball]
        }
    }
}

private enum SampleSport: String, CaseIterable, Hashable {
    case run, walk, hike, trailRun, strength, jumpRope, yoga, swim, tennis, basketball

    static let recent: [SampleSport] = [.run, .yoga, .tennis, .strength]

    var name: Text {
        switch self {
        case .run: Text("跑步", bundle: .module)
        case .walk: Text("快走", bundle: .module)
        case .hike: Text("徒步", bundle: .module)
        case .trailRun: Text("越野跑", bundle: .module)
        case .strength: Text("力量训练", bundle: .module)
        case .jumpRope: Text("跳绳", bundle: .module)
        case .yoga: Text("瑜伽", bundle: .module)
        case .swim: Text("游泳", bundle: .module)
        case .tennis: Text("网球", bundle: .module)
        case .basketball: Text("篮球", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .run, .trailRun: "figure.run"
        case .walk: "figure.walk"
        case .hike: "figure.hiking"
        case .strength: "figure.strengthtraining.traditional"
        case .jumpRope: "figure.jumprope"
        case .yoga: "figure.yoga"
        case .swim: "figure.pool.swim"
        case .tennis: "figure.tennis"
        case .basketball: "figure.basketball"
        }
    }
}
#endif
