import Contracts

/// The week's facts the story's pages are drawn from while the API's story carries only the
/// titles and the reader's hottest check-in: the Sunday summary's awards and counts, the
/// squad's check-ins that week and the reader's plan. The API's story will carry these pages
/// itself; until then `WeekStory.filled(with:)` draws them, with no AI lines.
public struct WeekFacts: Hashable, Sendable {
    /// A check-in that won an award, and what it won by.
    public struct Best: Hashable, Sendable {
        public let checkIn: CheckInID
        public let reactions: Int

        public init(checkIn: CheckInID, reactions: Int) {
            self.checkIn = checkIn
            self.reactions = reactions
        }
    }

    /// The reader.
    public let viewer: MemberID
    /// Who finished their plan (领奖台), in the order they joined the squad.
    public let planCompleted: [MemberID]
    /// Who has the crown: the most days on the podium, all of them on a tie.
    public let crown: [MemberID]
    /// The 请假条 with the most reactions, and how many it got.
    public let bestDisclaimer: Best?
    /// The squad's days trained and planned, added up over the members.
    public let squadTrained: Int
    public let squadPlanned: Int
    /// The reader's own counts.
    public let myPlanned: Int
    public let myReactionsReceived: Int
    /// The squad's check-ins counted for the week, every member's.
    public let checkIns: [CheckIn]
    /// The reader's plan for the week, Monday first; nil when it couldn't be read.
    public let plan: [PlanDay]?

    public init(
        viewer: MemberID, planCompleted: [MemberID], crown: [MemberID],
        bestDisclaimer: Best?, squadTrained: Int, squadPlanned: Int, myPlanned: Int,
        myReactionsReceived: Int, checkIns: [CheckIn], plan: [PlanDay]?
    ) {
        self.viewer = viewer
        self.planCompleted = planCompleted
        self.crown = crown
        self.bestDisclaimer = bestDisclaimer
        self.squadTrained = squadTrained
        self.squadPlanned = squadPlanned
        self.myPlanned = myPlanned
        self.myReactionsReceived = myReactionsReceived
        self.checkIns = checkIns
        self.plan = plan
    }
}

extension WeekStory {
    /// The story with every page the API doesn't send yet drawn from the week's facts. A page
    /// the API sends is kept as it is.
    public func filled(with facts: WeekFacts) -> WeekStory {
        WeekStory(
            status: status, squad: squad, squadName: squadName, week: week, order: order,
            podium: podium ?? facts.podium(titles: titles), titles: titles,
            myWeek: myWeek ?? facts.myWeek(week), hottest: hottest, meals: meals ?? facts.meals,
            bestDisclaimer: bestDisclaimer ?? facts.bestDisclaimerPage, ending: ending ?? facts.ending)
    }
}

extension WeekFacts {
    /// The crown winner in the middle, the others who finished their plan beside them; their
    /// first titles' 颁奖词 and moves when the titles are in.
    func podium(titles: [MemberTitles]) -> Podium? {
        guard let champion = crown.first ?? planCompleted.first else { return nil }
        let sides = (crown.dropFirst() + planCompleted).reduce(into: [MemberID]()) { sides, member in
            if member != champion && !sides.contains(member) { sides.append(member) }
        }
        func first(_ member: MemberID) -> MemberTitles.Title? {
            titles.first { $0.member == member }?.titles.first
        }
        return Podium(
            champion: champion, sides: sides, speech: first(champion)?.speech, championMove: first(champion)?.move,
            sideMove: sides.first.flatMap(first)?.move)
    }

    /// The reader's Monday to Sunday: a 练了 day plays its first sport, else a 请假条 lies flat,
    /// else a planned rest day dozes. None when they checked in nothing all week.
    func myWeek(_ week: Week) -> MyWeek? {
        let mine = checkIns.filter { $0.member == viewer }
        guard !mine.isEmpty else { return nil }
        let kinds = Self.days(of: week).enumerated().map { index, day -> MyWeek.Day in
            let posts = mine.filter { $0.day == day }
            if let sport = posts.lazy.compactMap(\.trainedActivity).first {
                if case .sport(let known) = sport { return MyWeek.Day(day: day, kind: .trained(known)) }
                return MyWeek.Day(day: day, kind: .trained(nil))
            }
            if posts.contains(where: \.isDisclaimer) { return MyWeek.Day(day: day, kind: .disclaimer) }
            if let plan, index < plan.count, plan[index] == .rest { return MyWeek.Day(day: day, kind: .rest) }
            return MyWeek.Day(day: day, kind: .none)
        }
        return MyWeek(
            plan: myPlanned, days: kinds, healthyMeals: mine.count(where: \.isHealthyMeal),
            cheatMeals: mine.count(where: \.isCheatMeal), reactionsReceived: myReactionsReceived)
    }

    /// The squad's meals, each member eating what they logged more of (健康餐 on a tie).
    var meals: Meals? {
        let healthy = checkIns.count(where: \.isHealthyMeal)
        let cheat = checkIns.count(where: \.isCheatMeal)
        guard healthy + cheat > 0 else { return nil }
        var eaters: [Meals.Eater] = []
        for member in checkIns.map(\.member) where !eaters.contains(where: { $0.member == member }) {
            let posts = checkIns.filter { $0.member == member }
            let mine = (healthy: posts.count(where: \.isHealthyMeal), cheat: posts.count(where: \.isCheatMeal))
            guard mine.healthy + mine.cheat > 0 else { continue }
            eaters.append(Meals.Eater(member: member, more: mine.cheat > mine.healthy ? .cheat : .healthy))
        }
        return Meals(healthy: healthy, cheat: cheat, eaters: eaters)
    }

    /// The best 请假条, with its words from the squad's check-ins.
    var bestDisclaimerPage: BestDisclaimer? {
        guard let best = bestDisclaimer, let note = checkIns.first(where: { $0.id == best.checkIn }),
            case .disclaimer(let disclaimer) = note.entry
        else { return nil }
        return BestDisclaimer(
            checkIn: best.checkIn, author: note.member, text: disclaimer.text, reactions: best.reactions)
    }

    /// The squad's days against its plans; none when nobody trained, so a quiet week isn't told
    /// how short it fell.
    var ending: Ending? {
        guard squadTrained > 0 else { return nil }
        return Ending(done: squadTrained, plan: squadPlanned)
    }

    /// Monday to Sunday.
    private static func days(of week: Week) -> [LocalDay] {
        (0..<7).map { week.monday.adding(days: $0) }
    }
}

extension CheckIn {
    fileprivate var trainedActivity: Activity? {
        if case .trained(let training) = entry { training.activity } else { nil }
    }

    fileprivate var isDisclaimer: Bool {
        if case .disclaimer = entry { true } else { false }
    }

    fileprivate var isHealthyMeal: Bool {
        if case .healthyMeal = entry { true } else { false }
    }

    fileprivate var isCheatMeal: Bool {
        if case .cheatMeal = entry { true } else { false }
    }
}
