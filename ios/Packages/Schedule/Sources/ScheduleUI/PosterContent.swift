import Contracts
import DesignSystem
import ScheduleDomain

/// What the poster shows for a week, worked out from the store: plain values the view draws,
/// so the rules for each row's look test without a simulator.
struct PosterContent: Equatable {
    /// How a lane looks.
    enum Look: Equatable {
        case plain
        /// Today's lane, a shade darker.
        case today
        /// The selected day: white, so it reads as picked up.
        case held
    }

    /// The bottom right of the poster.
    enum Tally: Equatable {
        /// This week (本周 2/5) or a past one (练了 4/5): days trained against days planned.
        case trained(Int, planned: Int, isPast: Bool)
        /// Next week: 5 练 2 休.
        case planned(train: Int, rest: Int)
        /// The 我的每周计划: 每周训练 4 天.
        case typical(train: Int)
    }

    enum Paint: Equatable {
        /// The squad's scene this week.
        case thisWeek
        /// A week that is over, in its own scene; the gym's for a week the squad has no 战报 of.
        case scene(SceneTheme)
        case graphite
    }

    struct Lane: Equatable, Identifiable {
        let index: Int
        let day: LocalDay
        let isToday: Bool
        let plan: PlanDay
        let mark: DayMark
        let look: Look
        var id: Int { index }

        /// What the lane says and how it is marked (`DayMark.face(of:)`). A day being changed
        /// shows the plan, so the pick reads as made.
        var face: (shown: PlanDay, mark: DayMark) {
            let face = mark.face(of: plan)
            guard look == .held, face.shown != plan else { return face }
            return (plan, .none)
        }
    }

    let nickname: String
    /// The 我的每周计划 rather than a week: no number or dates, in the brand's graphite.
    let isTemplate: Bool
    /// What the poster wears (Tracy, 2026-11-08): a week that is over wears the scene the squad
    /// trained on that week, this week the squad's scene now, and next week and the 我的每周计划,
    /// whose scene isn't picked yet, the brand's graphite.
    let paint: Paint
    let weekStart: LocalDay
    /// The squad's week, W1 for the week the squad began.
    let weekNumber: Int
    let lanes: [Lane]
    let titles: [AwardTitle]
    let fuel: [FuelGoal]
    let fuelOpen: Bool
    /// This week's and later weeks' 饮食小目标 open from the poster.
    let fuelEditable: Bool
    let tally: Tally

    var weekEnd: LocalDay { weekStart.adding(days: WeeklyPlan.dayCount - 1) }

    /// The scene the poster is drawn in, `now` being the squad's this week; graphite draws
    /// nothing of a scene.
    func scene(now: SceneTheme) -> SceneTheme {
        if case .scene(let scene) = paint { scene } else { now }
    }

    /// The week as the member sees it now, with what they have hold of.
    init(
        sheet: WeekSheet, board: WeekBoard?, nickname: String, weekNumber: Int, fuelOpen: Bool, typingFuel: String = ""
    ) {
        self.nickname = nickname
        isTemplate = false
        weekStart = sheet.weekStart
        self.weekNumber = weekNumber
        let days = board?.days ?? sheet.plan
        let tense = board?.tense ?? .past
        paint =
            switch tense {
            case .current: .thisWeek
            case .upcoming, .template: .graphite
            case .past: .scene(sheet.scene.flatMap { SceneTheme(rawValue: $0.rawValue) } ?? .gym)
            }
        lanes = days.indices.map { index in
            let held = board?.focus == .selected(index)
            let isToday = board?.today == index
            let look: Look = if held { .held } else if isToday { .today } else { .plain }
            return Lane(
                index: index, day: sheet.weekStart.adding(days: index), isToday: isToday, plan: days[index],
                mark: sheet.marks[index], look: look)
        }
        titles = tense == .past ? sheet.titles : []
        // A goal being typed shows on the poster as it is written.
        let typed = typingFuel.trimmingCharacters(in: .whitespacesAndNewlines)
        fuel = typed.isEmpty ? sheet.fuel : sheet.fuel + [.own(typed)]
        fuelEditable = tense != .past
        self.fuelOpen = fuelOpen && fuelEditable
        let planned = days.count { $0 != .rest }
        switch tense {
        case .upcoming: tally = .planned(train: planned, rest: days.count - planned)
        case .current: tally = .trained(sheet.trainedDays, planned: planned, isPast: false)
        case .past, .template: tally = .trained(sheet.trainedDays, planned: planned, isPast: true)
        }
    }

    /// The 我的每周计划 as the member plans it: every day open, nothing checked in, no 饮食小目标.
    init(template board: WeekBoard, nickname: String) {
        self.nickname = nickname
        isTemplate = true
        paint = .graphite
        weekStart = board.weekStart
        weekNumber = 0
        lanes = board.days.indices.map { index in
            Lane(
                index: index, day: board.weekStart.adding(days: index), isToday: false, plan: board.days[index],
                mark: .none, look: board.focus == .selected(index) ? .held : .plain)
        }
        titles = []
        fuel = []
        fuelOpen = false
        fuelEditable = false
        tally = .typical(train: board.plannedDays)
    }

    /// The same week to save as a picture: nothing held, the goals shut.
    var forSaving: PosterContent {
        PosterContent(
            nickname: nickname, isTemplate: isTemplate, paint: paint, weekStart: weekStart, weekNumber: weekNumber,
            lanes: lanes.map {
                Lane(
                    index: $0.index, day: $0.day, isToday: $0.isToday, plan: $0.plan, mark: $0.mark,
                    look: $0.isToday ? .today : .plain)
            },
            titles: titles, fuel: fuel, fuelOpen: false, fuelEditable: false, tally: tally)
    }

    private init(
        nickname: String, isTemplate: Bool, paint: Paint, weekStart: LocalDay, weekNumber: Int, lanes: [Lane],
        titles: [AwardTitle],
        fuel: [FuelGoal],
        fuelOpen: Bool,
        fuelEditable: Bool, tally: Tally
    ) {
        self.nickname = nickname
        self.isTemplate = isTemplate
        self.paint = paint
        self.weekStart = weekStart
        self.weekNumber = weekNumber
        self.lanes = lanes
        self.titles = titles
        self.fuel = fuel
        self.fuelOpen = fuelOpen
        self.fuelEditable = fuelEditable
        self.tally = tally
    }
}
