#if canImport(SwiftUI)
import Contracts
import DesignSystem
import DesignSystemUI
import OnboardingDomain
import SportsUI
import SwiftUI

/// 平时练什么？, step 3: the sports the member usually does. 最常见 in a two-column grid, 更多 as
/// pills, 其他 to name one, and a search over every sport. Each pick changes the character into
/// the sport's kit; the picks become the choices for the week that follows.
struct SportsStep: View {
    let model: SignUpModel
    @State private var query = ""
    @State private var isNaming = false
    @State private var customName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [GridItem(.flexible(), spacing: Space.xs), GridItem(.flexible(), spacing: Space.xs)]

    var body: some View {
        StepPage(
            step: .sports, title: Text("平时练什么？", bundle: .module), character: model.myCharacter, onBack: model.back
        ) {
            VStack(alignment: .leading, spacing: Space.m) {
                SearchField(text: $query, prompt: Text("搜索", bundle: .module))
                    .accessibilityIdentifier("sports.search")
                if query.isEmpty {
                    common
                    more
                } else {
                    results
                }
            }
        } actions: {
            StepButton(
                title: Text("下一步", bundle: .module), isWorking: false, isEnabled: !model.sports.picked.isEmpty,
                action: model.finishSports
            )
            .accessibilityIdentifier("sports.done")
            Button(action: model.skipSports) {
                Text("以后再选", bundle: .module)
            }
            .buttonStyle(TextButtonStyle())
            .accessibilityIdentifier("sports.skip")
        }
    }

    private var common: some View {
        VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(Text("最常见", bundle: .module))
            LazyVGrid(columns: columns, spacing: Space.xs) {
                ForEach(SportPicks.common, id: \.self) { sport in
                    row(.sport(sport))
                }
            }
        }
    }

    private var more: some View {
        VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(Text("更多", bundle: .module))
            FlowRow {
                ForEach(SportPicks.more, id: \.self) { sport in
                    pill(.sport(sport))
                }
                // Sports picked by search or named under 其他 show here too, to take off.
                ForEach(extraPicks, id: \.key) { activity in
                    PickPill(activity.name, isSelected: true, isRemovable: true) { model.toggle(activity) }
                }
                PickPill(Text("其他", bundle: .module), systemImage: "plus", isSelected: isNaming) {
                    isNaming.toggle()
                }
                .accessibilityIdentifier("sports.other")
            }
            if isNaming {
                InputField(
                    text: $customName, label: Text("其他", bundle: .module), prompt: Text("比如：飞盘", bundle: .module),
                    limit: CustomSport.maxLength
                )
                .onSubmit(addCustom)
                .submitLabel(.done)
                .accessibilityIdentifier("sports.otherName")
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -Space.xs)))
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: isNaming)
    }

    private var results: some View {
        let found = Sport.matching(query)
        return VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(found, id: \.self) { sport in
                row(.sport(sport))
            }
            if found.isEmpty, let custom = try? CustomSport(query) {
                PickRow(Text("加上「\(custom.name)」", bundle: .module), systemImage: "plus", isSelected: false) {
                    model.toggle(.custom(custom))
                    query = ""
                }
                .accessibilityIdentifier("sports.addCustom")
            }
        }
    }

    private func row(_ activity: Activity) -> some View {
        PickRow(activity.name, systemImage: activity.symbol, isSelected: model.sports.contains(activity)) {
            model.toggle(activity)
        }
        .accessibilityIdentifier("sports.\(activity.key)")
    }

    private func pill(_ activity: Activity) -> some View {
        PickPill(activity.name, isSelected: model.sports.contains(activity)) { model.toggle(activity) }
            .accessibilityIdentifier("sports.\(activity.key)")
    }

    /// Picks that are in neither 最常见 nor 更多.
    private var extraPicks: [Activity] {
        let shown = Set((SportPicks.common + SportPicks.more).map(Activity.sport))
        return model.sports.picked.filter { !shown.contains($0) }
    }

    private func addCustom() {
        guard let custom = try? CustomSport(customName) else { return }
        if !model.sports.contains(.custom(custom)) { model.toggle(.custom(custom)) }
        customName = ""
        isNaming = false
    }
}
#endif
