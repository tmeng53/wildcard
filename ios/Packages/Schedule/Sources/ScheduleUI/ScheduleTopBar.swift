#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import ScheduleDomain
import SwiftUI

// 出赛表's top bar, under the navigation bar's back button: the page's title and the week chips
// (本周, 下周, and 往期, the system menu of the weeks before; Tracy, 2026-11-21: a chip for each
// past week ran off the screen) with the 我的每周计划 after them. 存图 sits in the navigation bar, across from the back button.

extension ScheduleView {
    // MARK: Top bar

    /// The title and the week chips.
    var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(copy: "出赛表", bundle: .module)
                .typeStyle(TypeRamp.largeTitle)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .padding(.top, Space.xxs)
                .accessibilityAddTraits(.isHeader)
            CategoryBar(pageChips, selection: pageSelection)
                .frame(maxWidth: .infinity)
        }
    }

    /// 存图, in the navigation bar; the 我的每周计划 is no one week's poster to share.
    var saveItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if !store.showsTemplate {
                saveButton
            }
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        // An icon only, in the bar's round glass like the back button across from it.
        .accessibilityLabel(Text(copy: "存图", bundle: .module))
        .disabled(store.sheet == nil || model.saving != .idle && model.saving != .failed)
        .accessibilityIdentifier("schedule.save")
    }

    /// The weeks, then the 我的每周计划 after a hairline.
    private var pageChips: [CategoryBarItem<SchedulePage>] {
        guard !store.weeks.isEmpty else { return [] }
        return weekChips + [
            CategoryBarItem(
                id: .template, title: Text(copy: "我的每周计划", bundle: .module),
                systemImage: WeekPosterHeading.templateSymbol,
                startsGroup: true, accessibilityIdentifier: "schedule.template")
        ]
    }

    private var weekChips: [CategoryBarItem<SchedulePage>] {
        guard let thisWeek = store.today?.weekStart else { return [] }
        let now = store.weeks.filter { $0 >= thisWeek }.map { week in
            CategoryBarItem(
                id: SchedulePage.week(week),
                title: week == thisWeek ? Text(copy: "本周", bundle: .module) : Text(copy: "下周", bundle: .module),
                accessibilityIdentifier: "schedule.week.\(week)")
        }
        // The weeks before, newest first, then the squad's weeks before the member joined: one
        // greyed line, never a page.
        var past = store.weeks.filter { $0 < thisWeek }.reversed().map { week in
            CategoryBarItem(
                id: SchedulePage.week(week),
                title: Text(verbatim: ScheduleLabels.week(store.profile?.weekNumber(of: week) ?? 1)),
                accessibilityIdentifier: "schedule.week.\(week)")
        }
        guard let latest = past.first else { return now }
        if store.profile?.startsWithNotYetJoined(store.weeks) == true {
            past.append(
                CategoryBarItem(
                    id: SchedulePage.notYetJoined, title: Text(copy: "还未入队", bundle: .module),
                    accessibilityIdentifier: "schedule.notYetJoined", isEnabled: false))
        }
        return now + [
            CategoryBarItem(
                id: latest.id, title: Text(copy: "往期", bundle: .module), accessibilityIdentifier: "schedule.past",
                options: past)
        ]
    }

    private var pageSelection: Binding<SchedulePage> {
        Binding(
            get: {
                store.showsTemplate
                    ? .template : .week(store.shownWeek ?? store.today?.weekStart ?? LocalDay(at: .now, in: .current))
            },
            set: { page in
                switch page {
                case .week(let week): model.show(week)
                case .template: model.showTemplate()
                case .notYetJoined: break
                }
            })
    }
}
#endif
