#if os(iOS)
import AvatarArt
import AvatarDomain
import CharacterEditorDomain
import CharacterEditorUI
import Contracts
import Foundation
import Observation
import OnboardingDomain

/// Sign-up on screen: which step is showing, each step's draft, and the calls to the backend.
/// Each step's button saves what it needs before the next step shows, so going back and forth
/// never loses a pick.
@MainActor @Observable
public final class SignUpModel {
    public private(set) var step: SignUpStep = .welcome
    /// Whether the last move went forward, so the next screen slides in from the right side.
    private(set) var isGoingForward = true

    /// The look the open screen's middle character wears, which 角色和昵称 starts from.
    var welcomeLook: Outfit?
    private(set) var editor: CharacterEditorModel?
    private(set) var character: NewCharacter?
    /// The character just made, beside each step's title and on the stage at 上场.
    private(set) var myCharacter: CastMember?

    var squad: SquadDraft
    private(set) var preview: Lookup = .none
    /// The heads of the squad found, under its name: its members' characters, standing still.
    private(set) var previewHeads: [CastMember] = []
    private(set) var joined: JoinedSquad?
    /// The teammates who welcome the member at 上场, the earliest to join first.
    private(set) var teammates: [CastMember] = []

    private(set) var sports = SportPicks()
    private(set) var week: WeekDraft?

    /// A call under way: the step's button shows it's busy and can't be tapped twice.
    private(set) var isWorking = false
    /// What went wrong with the step's last call, until the member changes something.
    private(set) var failure: SignUpError?

    /// The invite code found while looking one up.
    enum Lookup: Equatable {
        case none
        case looking(InviteCode)
        case found(SquadPreview)
        case failed(InviteCode, SignUpError)
    }

    /// This week's days, Monday first, for the poster's dates.
    let weekDays: [LocalDay]
    /// The week's number in the year, the poster's W43.
    let weekNumber: Int

    @ObservationIgnored private let service: any SignUpService
    /// How many of this week's days are over: 0 on its first day.
    @ObservationIgnored let daysGone: Int

    /// `invite`: the code an invite link carried. `nickname`: the name Sign in with Apple shared,
    /// to start the nickname from. `now` in `timeZone` says which week the plan is for and which
    /// of its days are over, by the member's day as the API counts it (until 3am it is still the
    /// day before); weeks start on Monday. `hasAgreedToAI`: the account consented to AI writing
    /// before, so 你的小队 doesn't ask again.
    public init(
        service: any SignUpService, invite: InviteCode?, nickname: String, now: Date,
        in timeZone: TimeZone = .current, hasAgreedToAI: Bool = false
    ) {
        self.service = service
        asksForAIConsent = !hasAgreedToAI
        self.nickname = nickname
        squad = SquadDraft(invite: invite, suggestedName: "")
        let today = LocalDay(at: now, in: timeZone)
        weekDays = (0..<WeeklyPlan.dayCount).map { today.weekStart.adding(days: $0) }
        daysGone = today.weekday - 1
        weekNumber = today.weekOfYear
    }

    /// The nickname so far, for the squad's suggested name and the poster.
    private(set) var nickname: String

    // MARK: Moving between steps

    /// After 通过 Apple 继续 signs the member in.
    public func signedIn(name: String?) {
        failure = nil
        if let name, !name.isEmpty, editor == nil { nickname = name }
        show(.character)
    }

    /// Sign-in didn't work: the open screen says so above its button until the next try.
    public func signInFailed() {
        failure = .unavailable
    }

    /// Back a step, but not while a save is on its way: it would move the member on again when
    /// it lands, after they chose to go back.
    func back() {
        guard !isWorking, let previous = step.previous else { return }
        failure = nil
        show(previous, forward: false)
    }

    private func show(_ next: SignUpStep, forward: Bool = true) {
        isGoingForward = forward
        if next == .character, editor == nil {
            editor = try? CharacterEditorModel.placeholder(look: welcomeLook, nickname: nickname)
        }
        if next == .week, week == nil || week?.choices != WeekDraft(sports: sports.picked, daysGone: daysGone).choices {
            week = WeekDraft(sports: sports.picked, daysGone: daysGone)
        }
        step = next
    }

    // MARK: 角色和昵称

    func finishCharacter(_ edited: EditedCharacter) {
        guard let nickname = try? Nickname(edited.nickname) else { return }
        let made = NewCharacter(outfit: edited.outfit, persona: edited.persona, nickname: nickname)
        // A squad name the member hasn't touched follows the nickname.
        if squad.typedName.isEmpty || squad.typedName == Self.suggestedName(for: self.nickname) {
            squad.typedName = Self.suggestedName(for: nickname.text)
        }
        self.nickname = nickname.text
        perform { () async throws(SignUpError) in
            try await self.service.save(made)
            self.character = made
            if self.myCharacter?.look != made.outfit || self.myCharacter?.persona != made.persona {
                let character = CastMember(outfit: made.outfit, persona: made.persona)
                self.myCharacter = character
                // A character stays still beside a title until a sport is picked.
                await character.load(idle: false)
                if let wearing = self.sports.wearing { character.dress(for: wearing) }
            }
            self.show(.squad)
        }
    }

    /// 「Tracy 的小队」.
    static func suggestedName(for nickname: String) -> String {
        String(localized: "\(nickname) 的小队", bundle: .module)
    }

    // MARK: 你的小队

    func choose(_ choice: SquadDraft.Choice) {
        squad.choice = choice
        failure = nil
    }

    func typeCode(_ text: String) {
        squad.typedCode = text
        failure = nil
        guard let code = squad.code else {
            preview = .none
            return
        }
        if case .found(let found) = preview, found.code == code { return }
        preview = .looking(code)
        Task {
            do throws(SignUpError) {
                let found = try await service.preview(code)
                guard case .looking(code) = preview else { return }
                let heads = found.looks.map { CastMember(outfit: Outfit($0), persona: Persona($0)) }
                for head in heads { await head.load(idle: false) }
                guard case .looking(code) = preview else { return }
                previewHeads = heads
                preview = .found(found)
            } catch {
                if case .looking(code) = preview { preview = .failed(code, error) }
            }
        }
    }

    /// Whether 你的小队 shows the consent line under the button: AI writes the squad's weekly
    /// awards from what members write, and joining or making the squad agrees to it. Consent is the
    /// account's, given once: an account that already gave it never sees the line.
    let asksForAIConsent: Bool

    func typeName(_ text: String) {
        squad.typedName = text
        failure = nil
    }

    /// Whether 加入小队 or 建小队 can go: a squad found that has room, or a name the API takes, or the
    /// squad already joined or made.
    var canFinishSquad: Bool {
        if joined != nil { return true }
        switch squad.choice {
        case .join:
            if case .found(let found) = preview { return !found.isFull }
            return false
        case .create:
            return squad.name != nil
        }
    }

    func finishSquad() {
        // Back on 你的小队 after the squad was joined or made: it is settled, so carry on rather
        // than join or make another.
        if joined != nil {
            show(.sports)
            return
        }
        guard canFinishSquad else { return }
        let choice = squad.choice
        let code = squad.code
        let name = squad.name
        perform { () async throws(SignUpError) in
            if self.asksForAIConsent { try await self.service.agreeToAI() }
            let squad: JoinedSquad
            switch choice {
            case .join:
                guard let code else { return }
                squad = try await self.service.join(code)
            case .create:
                guard let name else { return }
                squad = try await self.service.create(named: name)
            }
            self.joined = squad
            self.teammates = squad.teammates.map { CastMember(outfit: $0.outfit, persona: $0.persona) }
            self.show(.sports)
        }
    }

    // MARK: 平时练什么？

    /// Picks or takes off a sport. A pick changes the character into its kit; taking off the
    /// one it wears changes it into the one picked before, or back into its own clothes.
    func toggle(_ activity: Activity) {
        switch sports.toggle(activity) {
        case .picked: myCharacter?.dress(for: activity)
        case .removed(changed: true): myCharacter?.dress(for: sports.wearing)
        case .removed(changed: false): break
        }
    }

    func finishSports() {
        show(.week)
    }

    /// 以后再选: on with no sports, so training days name none.
    func skipSports() {
        if sports.wearing != nil { myCharacter?.dress(for: nil) }
        sports = SportPicks()
        show(.week)
    }

    // MARK: 一周练几天？

    func selectDay(_ index: Int) {
        week?.select(index)
    }

    /// Sets the selected day; the character hops when a rest day becomes a training day.
    func setDay(_ day: PlanDay) {
        if week?.set(day) == true { hops += 1 }
    }

    /// Bumped each time a rest day becomes a training day.
    private(set) var hops = 0

    func finishWeek() {
        guard let days = week?.days else { return }
        perform { () async throws(SignUpError) in
            try await self.service.savePlan(days)
            self.show(.entrance)
        }
    }

    /// 跳过: no plan this week; 本周 counts against nothing until one is set.
    func skipWeek() {
        week = nil
        show(.entrance)
    }

    // MARK: 上场

    /// The squad's planned days this week, with the member's own once their plan is in.
    var squadGoal: (before: Int, after: Int) {
        let before = joined?.weekGoal ?? 0
        return (before, before + (week?.trainingDays ?? 0))
    }

    /// The squad the member is in once 上场 has played, when home takes over.
    public private(set) var finished: JoinedSquad?

    func finishEntrance() {
        guard finished == nil else { return }
        finished = joined
    }

    // MARK: Calls

    /// Runs one call at a time; a failure stays on the step for the member to try again.
    private func perform(_ work: @escaping @MainActor () async throws(SignUpError) -> Void) {
        guard !isWorking else { return }
        isWorking = true
        failure = nil
        Task {
            defer { isWorking = false }
            do throws(SignUpError) {
                try await work()
            } catch {
                failure = error
            }
        }
    }
}
#endif
