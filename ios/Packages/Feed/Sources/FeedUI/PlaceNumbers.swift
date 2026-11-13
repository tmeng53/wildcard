#if os(iOS)
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// A place's graphite card (approved ② and ③): numbers only, no icons. A place to train shows
/// 小队评分, 小队来过 N 次 and 来过的队友 N 人; a place to eat its meals' 健康, 好吃 and 卡价比 (whose ⓘ
/// says 卡路里性价比) and how often the squad came. A score nobody gave yet is —.
struct PlaceNumbers: View {
    @Environment(\.sceneTheme) private var theme
    @State private var explainsValue = false
    let page: PlacePage?
    let isForEating: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            if isForEating {
                let meals = page?.meals ?? .none
                stat(Self.decimal(meals.healthy), label: Text(copy: "健康", bundle: .module))
                stat(Self.decimal(meals.tasty), label: Text(copy: "好吃", bundle: .module))
                stat(Self.decimal(meals.calorieValue), label: valueLabel)
                stat(
                    "\(page?.visits ?? 0)", unit: Text(copy: "次", bundle: .module),
                    label: Text(copy: "来过", bundle: .module))
            } else {
                stat(Self.decimal(page?.stars), label: Text(copy: "小队评分", bundle: .module))
                stat(
                    "\(page?.visits ?? 0)", unit: Text(copy: "次", bundle: .module),
                    label: Text(copy: "小队来过", bundle: .module))
                stat(
                    "\(page?.people ?? 0)", unit: Text(copy: "人", bundle: .module),
                    label: Text(copy: "来过的队友", bundle: .module))
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(role: .bgInk, in: theme), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place.numbers")
    }

    /// 卡价比 with its ⓘ, which says what it is.
    private var valueLabel: some View {
        Button {
            explainsValue = true
        } label: {
            HStack(spacing: Space.xxs) {
                Text(copy: "卡价比", bundle: .module)
                Image(systemName: "info.circle")
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("place.valueInfo")
        .popover(isPresented: $explainsValue) {
            Text(copy: "卡路里性价比", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func stat(_ number: String, unit: Text? = nil, label: some View) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs / 2) {
                Text(verbatim: number)
                    .typeStyle(TypeRamp.scoreInline)
                if let unit {
                    unit.typeStyle(TypeRamp.label)
                }
            }
            .foregroundStyle(Color(role: .fgOnInk, in: theme))
            label
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// A score to one decimal, or — before anyone gave one.
    static func decimal(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }
}
#endif
