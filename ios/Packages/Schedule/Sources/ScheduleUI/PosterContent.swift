import Contracts
import ScheduleDomain

/// What the poster shows for a week, worked out from the store: plain values the view draws,
/// so the rules for each row's look test without a simulator.
struct PosterContent: Equatable {
    /// How a lane looks.
    enum Look: Equatable {
        case plain
        /// Today's lane, a shade darker.
        case today
        /// A training day the lifted rest day can swap with: outlined.
        case swapTarget
        /// The selected or lifted day: white, so it reads as picked up.
        case held
    }

    /// The bottom right of the poster.
    enum Tally: Equatable {
        /// This week (本周 2/5) or a past one (练了 4/5): days trained against days planned.
        case trained(Int, of: Int, isPast: Bool)
        /// Next week: 5 练 2 休.
        case planned(train: Int, rest: Int)
    }

    struct Lane: Equatable, Identifiable {
        let index: Int
        let day: LocalDay
        let isToday: Bool
        let plan: PlanDay
        let mark: DayMark
        let look: Look
        let isEditable: Bool
        var id: Int { index }
        /// Whether the lane is lifted rather than selected, for its bounce.
        let isLifted: Bool
    }

    let nickname: String
    let weekStart: LocalDay
    let lanes: [Lane]
    let titles: [AwardTitle]
    let openTitle: AwardTitle?
    let fuel: [FuelGoal]
    let fuelOpen: Bool
    /// Only next week's 饮食小目标 open from the poster.
    let fuelEditable: Bool
    let tally: Tally

    var weekEnd: LocalDay { weekStart.adding(days: WeeklyPlan.dayCount - 1) }

    /// The week as the member sees it now, with what they have hold of.
    init(sheet: WeekSheet, board: WeekBoard?, nickname: String, openTitle: AwardTitle?, fuelOpen: Bool) {
        self.nickname = nickname
        weekStart = sheet.weekStart
        let days = board?.days ?? sheet.plan
        let tense = board?.tense ?? .past
        lanes = days.indices.map { index in
            var held = false
            var lifted = false
            switch board?.focus {
            case .selected(let selected)?: held = selected == index
            case .lifted(let picked)?: (held, lifted) = (picked == index, picked == index)
            default: break
            }
            let isToday = board?.today == index
            let look: Look =
                if held { .held } else if board?.isSwapTarget(index) == true { .swapTarget } else if isToday {
                    .today
                } else { .plain }
            return Lane(
                index: index, day: sheet.weekStart.adding(days: index), isToday: isToday, plan: days[index],
                mark: sheet.marks[index], look: look, isEditable: board?.isEditable(index) ?? false, isLifted: lifted)
        }
        titles = tense == .past ? sheet.titles : []
        self.openTitle = titles.contains { $0 == openTitle } ? openTitle : nil
        fuel = sheet.fuel
        fuelEditable = tense == .upcoming
        self.fuelOpen = fuelOpen && fuelEditable
        let planned = days.count { $0 != .rest }
        switch tense {
        case .upcoming: tally = .planned(train: planned, rest: days.count - planned)
        case .current: tally = .trained(sheet.trainedDays, of: planned, isPast: false)
        case .past: tally = .trained(sheet.trainedDays, of: planned, isPast: true)
        }
    }

    /// The same week to save as a picture: nothing held, no award line open, the goals shut.
    var forSaving: PosterContent {
        PosterContent(
            nickname: nickname, weekStart: weekStart,
            lanes: lanes.map {
                Lane(
                    index: $0.index, day: $0.day, isToday: $0.isToday, plan: $0.plan, mark: $0.mark,
                    look: $0.isToday ? .today : .plain, isEditable: false, isLifted: false)
            },
            titles: titles, openTitle: nil, fuel: fuel, fuelOpen: false, fuelEditable: false, tally: tally)
    }

    private init(
        nickname: String, weekStart: LocalDay, lanes: [Lane], titles: [AwardTitle], openTitle: AwardTitle?,
        fuel: [FuelGoal], fuelOpen: Bool, fuelEditable: Bool, tally: Tally
    ) {
        self.nickname = nickname
        self.weekStart = weekStart
        self.lanes = lanes
        self.titles = titles
        self.openTitle = openTitle
        self.fuel = fuel
        self.fuelOpen = fuelOpen
        self.fuelEditable = fuelEditable
        self.tally = tally
    }
}
