#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// Every sport, by category with search (spec P4). One pick closes it.
struct SportPicker: View {
    @Environment(\.sceneTheme) private var theme
    let selected: Activity
    let pick: (Activity) -> Void
    @State private var query = ""
    @State private var category = SportCategory.runWalk

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                SearchField(text: $query, prompt: Text("搜索运动", bundle: .module))
                    .padding(.horizontal, Space.pageMargin)
                    .accessibilityIdentifier("sports.search")
                if query.isEmpty {
                    CategoryBar(categories, selection: $category)
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

    private var shown: [Sport] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return category.sports }
        return Sport.allCases.filter {
            $0.localizedName.localizedCaseInsensitiveContains(needle)
                || $0.rawValue.localizedCaseInsensitiveContains(needle)
        }
    }

    private var categories: [CategoryBarItem<SportCategory>] {
        SportCategory.allCases.map {
            CategoryBarItem(id: $0, title: $0.name, accessibilityIdentifier: "sports.category.\($0.rawValue)")
        }
    }
}
#endif
