#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// Every sport, by category with search (spec P4), for a sheet. One pick closes it: the caller
/// dismisses the sheet in `pick`.
public struct SportPicker: View {
    @Environment(\.sceneTheme) private var theme
    let selected: Activity
    let pick: (Activity) -> Void
    @State private var query = ""
    /// The tab shown: the first until one is picked.
    @State private var picked: String?

    public init(selected: Activity, pick: @escaping (Activity) -> Void) {
        self.selected = selected
        self.pick = pick
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                SearchField(text: $query, prompt: Text("搜索运动", bundle: .module))
                    .padding(.horizontal, Space.pageMargin)
                    .accessibilityIdentifier("sports.search")
                if query.isEmpty, let category {
                    CategoryBar(
                        categories,
                        selection: Binding {
                            category.id
                        } set: {
                            picked = $0
                        })
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 2),
                    spacing: Space.xs
                ) {
                    ForEach(shown, id: \.self) { sport in
                        PickRow(sport.name, systemImage: sport.symbol, isSelected: selected == .sport(sport)) {
                            pick(.sport(sport))
                        }
                        .accessibilityIdentifier("sports.tile.\(sport.rawValue)")
                    }
                }
                .padding(.horizontal, Space.pageMargin)
            }
            .padding(.vertical, Space.m)
        }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var catalog: SportCatalog { SportList.shared.catalog }

    private var category: SportCatalog.Category? {
        catalog.categories.first { $0.id == picked } ?? catalog.categories.first
    }

    private var shown: [Sport] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? category?.offered ?? [] : catalog.matching(query)
    }

    private var categories: [CategoryBarItem<String>] {
        catalog.categories.filter { !$0.offered.isEmpty }.map {
            CategoryBarItem(id: $0.id, title: $0.name, accessibilityIdentifier: "sports.category.\($0.id)")
        }
    }
}
#endif
