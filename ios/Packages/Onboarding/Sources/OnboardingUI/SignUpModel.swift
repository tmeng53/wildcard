#if os(iOS)
import AvatarArt
import AvatarDomain
import CharacterEditorDomain
import CharacterEditorUI
import Contracts
import DesignSystemUI
import Foundation
import DesignSystem
import HealthUI
import LocationDomain
import Observation
import OnboardingDomain
import ScenePickDomain

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
    /// The pieces still locked for the member, read once they are signed in.
    /// The member's 商店街, once read; the editor offers the starter street until then.
    private var stock: StreetStock?
    internal(set) var character: NewCharacter?
    /// The character just made, beside each step's title and on the stage at 上场.
    internal(set) var myCharacter: CastMember?

    var squad: SquadDraft
    private(set) var preview: Lookup = .none
    /// The heads of the squad found, under its name: its members' characters, standing still.
    private(set) var previewHeads: [CastMember] = []
    private(set) var joined: JoinedSquad?
    /// The squad joined or made, which the app keeps until 上场 to carry on a closed sign-up.
    public var joinedSquad: SquadID? { joined?.id }
    /// The teammates who welcome the member at 上场, the earliest to join first.
    private(set) var teammates: [CastMember] = []

    var sports = SportPicks()
    /// 关于你's birthday on the flip clock, saved only once the member turned a card.
    var birthday = BirthdayDraft()
    internal(set) var week: WeekDraft?

    /// The member was in a squad and is in none now: they only join or make one, as the character
    /// they have, keeping everything else they saved (Tracy, 2026-11-11).
    public internal(set) var isRejoining = false

    /// The member's request to a squad whose captain lets members in (入队申请), from 申请加入 until
    /// they are in, withdraw it or choose again after a no: 等队长同意 shows it.
    public internal(set) var request: JoinRequest?
    /// The asked squad's heads and its captain's, standing still, on 等队长同意.
    internal(set) var requestHeads: [CastMember] = []
    internal(set) var captainHead: CastMember?
    /// The member went past 本周目标: choosing a squad again after a captain's no carries on from
    /// there rather than through the steps they did.
    internal(set) var pastWeek = false

    /// Bumped each time a rest day becomes plain 训练.
    internal(set) var hops = 0

    /// Whether the member made the squad they are in, rather than joined one: they pick its scene.
    public private(set) var madeTheSquad = false
    /// 这周在哪练？'s five cartons, once the squad is made.
    private(set) var scenePicker: ScenePicker?
    /// The picked carton opening over 这周在哪练？.
    var reveal: SceneReveal?
    /// The scene picked on 这周在哪练？, which the member drops onto at home rather than playing
    /// 上场; nil for whoever joined a squad.
    public private(set) var landing: SceneTheme?

    /// A call under way: the step's button shows it's busy and can't be tapped twice.
    private(set) var isWorking = false
    /// What went wrong with the step's last call, until the member changes something.
    internal(set) var failure: SignUpError?

    /// This week's days, Monday first, for the poster's weekday names.
    let weekDays: [LocalDay]

    @ObservationIgnored let service: any SignUpService
    /// Apple Health, which 连上 Apple 健康 connects; nil or unavailable skips that step.
    let health: HealthConnection?
    /// Whether 连上 Apple 健康 is asking the system now.
    var isConnectingHealth = false
    /// The phone's approximate location, which 打开大概位置 asks for; nil skips that step.
    let location: LocationSharing?
    /// How many of this week's days are over: 0 on its first day. Home's first week counts only
    /// from today.
    @ObservationIgnored let daysGone: Int
    /// The member's today, the last day a birthday can be.
    @ObservationIgnored let today: LocalDay

    /// `nickname`: the name Sign in with Apple shared,
    /// to start the nickname from. `now` in `timeZone` says which week the plan is for and which
    /// of its days are over, by the member's day as the API counts it; weeks start on Monday. `hasAgreedToAI`: the account consented to AI writing
    /// before, so 你的小队 doesn't ask again. `health`: the app's Apple Health, which 连上 Apple 健康
    /// connects. `location`: the app's location for the coach's weather, which 打开大概位置 asks for.
    public init(
        service: any SignUpService, nickname: String, now: Date,
        in timeZone: TimeZone = .current, hasAgreedToAI: Bool = false, health: HealthConnection? = nil,
        location: LocationSharing? = nil
    ) {
        self.service = service
        self.health = health
        self.location = location
        asksForAIConsent = !hasAgreedToAI
        self.nickname = nickname
        squad = SquadDraft(invite: nil, suggestedName: "", timeZone: timeZone.identifier)
        let today = LocalDay(at: now, in: timeZone)
        weekDays = (0..<WeeklyPlan.dayCount).map { today.weekStart.adding(days: $0) }
        daysGone = today.weekday - 1
        self.today = today
    }

    /// The nickname so far, for the squad's suggested name and the poster.
    internal(set) var nickname: String

    // MARK: Moving between steps

    /// After 通过 Apple 继续 signs the member in.
    public func signedIn(name: String?) {
        failure = nil
        if let name, !name.isEmpty, editor == nil { nickname = name }
        show(.character)
        Task { await readStock() }
    }

    /// Carries on a sign-up closed after 你的小队, at 关于你 with its saved character; false if not.
    /// `rejoining`: a member back in no squad, who carries on at 上场 or 这周在哪练？ instead.
    public func resume(in squad: SquadID, madeIt: Bool, rejoining: Bool = false) async -> Bool {
        guard let resumed = try? await service.resume(in: squad) else { return false }
        (joined, madeTheSquad, character) = (resumed.squad, madeIt, resumed.character)
        isRejoining = rejoining && resumed.character != nil
        teammates = resumed.squad.teammates.map { CastMember(outfit: $0.outfit, persona: $0.persona) }
        if let made = resumed.character {
            (nickname, myCharacter) = (made.nickname.text, CastMember(outfit: made.outfit, persona: made.persona))
            stock = await service.stock()
            editor = try? CharacterEditorModel.placeholder(
                look: made.outfit, persona: made.persona, nickname: nickname, stock: stock)
            await myCharacter?.load(idle: false)
        }
        show(afterSquad)
        return true
    }

    /// Sign-in didn't work: the open screen says so above its button until the next try.
    public func signInFailed() {
        failure = .unavailable
    }

    /// Back a step, but not while a save is on its way: it would move the member on again when
    /// it lands, after they chose to go back.
    func back() {
        guard !isWorking, !isPickingScene, !isConnectingHealth, !isAskingLocation, reveal == nil else { return }
        let previous =
            isRejoining ? step.previousRejoining : step.previous(hasHealth: hasHealth, hasLocation: hasLocation)
        guard let previous else { return }
        failure = nil
        show(previous, forward: false)
    }

    func show(_ next: SignUpStep, forward: Bool = true) {
        isGoingForward = forward
        if next == .character, editor == nil {
            editor = try? CharacterEditorModel.placeholder(look: welcomeLook, nickname: nickname, stock: stock)
        }
        let days = joined?.daysPerMember ?? squad.daysPerMember
        if next == .week, week == nil || week?.choices != WeekDraft(sports: sports.picked, days: days).choices {
            week = WeekDraft(sports: sports.picked, days: days)
        }
        if step == .week, next < .week {
            // Back from the week: the character wears the sport picked last again, not the
            // scene's kit the week's poster put on it.
            myCharacter?.dress(for: sports.wearing)
        }
        if next == .scene, scenePicker == nil, let joined {
            scenePicker = .newSquad(service: SignUpScenePick(service: service, squad: joined.id))
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

    // MARK: 你的小队

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
            if case .found(let found) = preview { return !found.isFull && (!found.needsApproval || squad.noteIsValid) }
            return false
        case .create:
            return squad.name != nil
        }
    }

    func finishSquad() {
        // Back on 你的小队 after the squad was joined or made: it is settled, so carry on rather
        // than join or make another.
        if joined != nil {
            show(afterSquad)
            return
        }
        guard canFinishSquad else { return }
        let choice = squad.choice
        let code = squad.code
        // A 备注 goes only to a squad whose captain reads it.
        let note = asksCaptain ? squad.note : nil
        let name = squad.name
        let daysPerMember = squad.daysPerMember
        let timeZone = squad.timeZone
        perform { () async throws(SignUpError) in
            if self.asksForAIConsent { try await self.service.agreeToAI() }
            let squad: JoinedSquad
            switch choice {
            case .join:
                guard let code else { return }
                switch try await self.service.join(code, note: note) {
                case .joined(let joined): squad = joined
                case .asked(let request):
                    await self.asked(request)
                    self.show(self.afterSquad)
                    return
                }
            case .create:
                guard let name else { return }
                squad = try await self.service.create(
                    named: name, daysPerMember: daysPerMember, timeZone: timeZone)
            }
            (self.joined, self.request) = (squad, nil)
            self.madeTheSquad = choice == .create
            self.teammates = squad.teammates.map { CastMember(outfit: $0.outfit, persona: $0.persona) }
            self.show(self.afterSquad)
        }
    }

    // MARK: 这周在哪练？

    /// 「确认」: saves the pick, then its carton opens.
    func confirmScene() {
        guard let picker = scenePicker, picker.canConfirm else { return }
        failure = nil
        Task {
            guard let unboxing = await picker.confirm(), let scene = picker.selection else {
                switch picker.phase {
                case .failed(.unavailable): failure = .unavailable
                // The squad has its scene already (an earlier try saved, its answer lost) or
                // the week closed: home opens on whatever the squad trains on, with no drop.
                case .failed(.notAllowed): finished = joined
                case .choosing, .saving, .picked: break
                }
                return
            }
            reveal = SceneReveal(unboxing: unboxing, scene: scene, startedAt: .now)
        }
    }

    /// Whether the pick is on its way.
    var isPickingScene: Bool { scenePicker?.phase == .saving }

    /// The picked scene fills the screen: sign-up is over, and home takes over on it.
    func sceneRevealed() {
        guard finished == nil, let reveal else { return }
        landing = reveal.scene
        finished = joined
    }

    // MARK: 上场

    /// The squad the member is in once 上场 has played, or the scene picked has filled the
    /// screen, when home takes over.
    public private(set) var finished: JoinedSquad?

    func finishEntrance() {
        guard finished == nil else { return }
        finished = joined
    }

    // MARK: Calls

    /// Runs one call at a time; a failure stays on the step for the member to try again.
    func perform(_ work: @escaping @MainActor () async throws(SignUpError) -> Void) {
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

extension SignUpModel {
    /// The member's own street goes into the editor, which may have opened on the starter street
    /// before it arrived.
    fileprivate func readStock() async {
        let known = stock != nil
        stock = await service.stock()
        if let editor, let stock, !known { try? editor.stock(stock) }
    }
}
#endif
