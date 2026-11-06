#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import ScheduleDomain
import SwiftUI

// 出赛表's top bar: 返回, the week chips with the 每周模板 after them, and 存图.

extension ScheduleView {
    // MARK: Top bar

    /// 返回 to 我, then the week chips and 存图.
    var topBar: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", action: back)
                .accessibilityIdentifier("schedule.back")
            chipRow
        }
    }

    private var chipRow: some View {
        HStack(spacing: Space.xs) {
            CategoryBar(pageChips, selection: pageSelection)
                .frame(maxWidth: .infinity)
            // The 每周模板 is no one week's poster to share.
            if !store.showsTemplate {
                saveButton
            }
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Label {
                Text("存图", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: Sizing.smallIcon + 2, weight: .medium))
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(store.sheet == nil || model.saving != .idle && model.saving != .failed)
        .accessibilityIdentifier("schedule.save")
    }

    /// The weeks, then the 每周模板 after a hairline.
    private var pageChips: [CategoryBarItem<SchedulePage>] {
        guard !store.weeks.isEmpty else { return [] }
        return weekChips + [
            CategoryBarItem(
                id: .template, title: Text("我的每周计划", bundle: .module), systemImage: WeekPosterHeading.templateSymbol,
                startsGroup: true, accessibilityIdentifier: "schedule.template")
        ]
    }

    private var weekChips: [CategoryBarItem<SchedulePage>] {
        let thisWeek = store.today?.weekStart
        return store.weeks.map { week in
            let title: Text =
                if week == thisWeek {
                    Text("本周", bundle: .module)
                } else if let thisWeek, week > thisWeek {
                    Text("下周", bundle: .module)
                } else {
                    Text(verbatim: ScheduleLabels.week(store.profile?.weekNumber(of: week) ?? 1))
                }
            return CategoryBarItem(id: .week(week), title: title, accessibilityIdentifier: "schedule.week.\(week)")
        }
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
                }
            })
    }
}
#endif
