#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import OnboardingDomain
import SportsUI
import SwiftUI

/// 平时练什么？, step 3: the sports the member usually does. 最常见 in a two-column grid, and 更多
/// for the shared sport picker, which has every sport. Each pick changes the character into the
/// sport's kit; the picks become the choices for the week that follows.
struct SportsStep: View {
    let model: SignUpModel
    @State private var isChoosing = false

    private let columns = [GridItem(.flexible(), spacing: Space.xs), GridItem(.flexible(), spacing: Space.xs)]

    var body: some View {
        StepPage(
            step: .sports, title: Text("平时练什么？", bundle: .module), character: model.myCharacter, onBack: model.back
        ) {
            VStack(alignment: .leading, spacing: Space.m) {
                common
                more
            }
        } actions: {
            StepButton(
                title: Text("下一步", bundle: .module), isWorking: false, isEnabled: !model.sports.picked.isEmpty,
                action: model.finishSports
            )
            .accessibilityIdentifier("sports.done")
            Button(action: model.skipSports) {
                Text("以后再说", bundle: .module)
            }
            .buttonStyle(TextButtonStyle())
            .accessibilityIdentifier("sports.skip")
        }
        .sheet(isPresented: $isChoosing) {
            SportPicker(selected: model.sports.picked.last ?? .sport("run"), recent: model.sports.picked) { activity in
                if !model.sports.contains(activity) { model.toggle(activity) }
                isChoosing = false
            }
        }
    }

    private var common: some View {
        VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(Text("最常见", bundle: .module))
            LazyVGrid(columns: columns, spacing: Space.xs) {
                ForEach(catalog.signUpCommon, id: \.self) { sport in
                    row(.sport(sport))
                }
            }
        }
    }

    private var more: some View {
        VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(Text("更多", bundle: .module))
            FlowRow {
                // Sports picked from the full list show here, to take off.
                ForEach(extraPicks, id: \.key) { activity in
                    PickPill(activity.name, isSelected: true, isRemovable: true) { model.toggle(activity) }
                }
                PickPill(Text("更多", bundle: .module), systemImage: "plus", isSelected: false) {
                    isChoosing = true
                }
                .accessibilityIdentifier("sports.other")
            }
        }
    }

    private func row(_ activity: Activity) -> some View {
        PickRow(activity.name, systemImage: activity.symbol, isSelected: model.sports.contains(activity)) {
            model.toggle(activity)
        }
        .accessibilityIdentifier("sports.\(activity.key)")
    }

    /// Picks that are not in 最常见.
    private var extraPicks: [Activity] {
        let shown = Set(catalog.signUpCommon.map(Activity.sport))
        return model.sports.picked.filter { !shown.contains($0) }
    }

    private var catalog: SportCatalog { SportList.shared.catalog }
}
#endif
