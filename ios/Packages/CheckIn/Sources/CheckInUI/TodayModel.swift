#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import Foundation
import HealthDomain
import HealthUI
import Observation
import SwiftUI

/// Where photos for a 练了 or a meal come from.
public enum PhotoSource: Sendable {
    /// The member adds them on the compose page: the camera or the system photo picker.
    case library
    /// Photos handed over up front, so UI tests can post without the system picker.
    case provided([PreparedPhoto])
}

/// The 今天 screen's state: the board, which step of a check-in is open, and the payoff. Views
/// animate its changes, so Reduce Motion applies.
@MainActor @Observable
public final class TodayModel {
    enum Step: Equatable {
        case scene
        case composing(CheckInKind)
        case disclaimer
    }

    /// What lands on the scene after a post: the bubble's line, and the post it opens once saved.
    struct Payoff: Equatable {
        let id: CheckInID
        let kind: CheckInKind
        let line: String?
        /// The post as the server saved it, once it has; its bubble opens it.
        var post: CheckIn?
    }

    /// Opening it closes a teammate's bubble, which would otherwise stay sharp over the blur.
    var isBurstOpen = false {
        didSet { if isBurstOpen { pats.dismissBubble() } }
    }
    /// Everyone else on the scene.
    let cast = SquadCast()
    /// 拍一拍 on the scene.
    let pats: PatStage
    /// The squad celebrating together on the scene (撞头, 叠罗汉, 人浪); off in UI tests that don't ask.
    let together: TogetherStage
    /// Bumps on each of my 练了: the ring under my feet draws, the squad cheers, the streamers fall.
    private(set) var celebrations = 0
    /// How long a notice at the top stays up.
    let noticeHold: Double
    private(set) var step = Step.scene

    /// Whether the app's tab bar shows: on the scene, but not while the 打卡 burst is open (a tap
    /// anywhere outside its capsules closes it), a check-in is being written (the compose and
    /// 请假条 pages take the whole screen) or the squad is dropping in, until 打卡 is back.
    public var showsTabBar: Bool {
        guard !holdsTabBar, opening == nil, shownLetter == nil else { return false }
        return switch step {
        case .scene: !isBurstOpen
        case .composing, .disclaimer: false
        }
    }

    /// The open compose page's state.
    private(set) var compose: ComposeModel?
    var payoff: Payoff?  // Its post is set by `deliver` once saved.
    /// Counts posts, so the one strong haptic fires on each.
    private(set) var posts = 0
    private(set) var isSending = false
    /// The latest post going out behind the scene, on 打卡's spot until it is told (`deliver`).
    var outgoing: Outgoing?
    /// The last post didn't go out; the open step says so and can try again.
    private(set) var sendFailed = false

    let photoSource: PhotoSource
    /// My character, as I made it once the home says so; the stand-in lifter until then. It does
    /// what a teammate's does in my pose (`TodayModel+Dress.swift`): my sport's kit and move once I
    /// 练了, my latest meal, my 请假条, sitting on a rest day, asleep at night.
    var player: CharacterPlayer?
    private(set) var myLook = PlaceholderCharacter.lifter
    private(set) var myPersona = Persona.energetic
    /// What my character has on and loops, so it changes only when that does.
    var worn: Worn?
    /// Keeps my kit off while a 练了's cheer plays, by the 练了 that holds it (counted by
    /// `dressHolds`); it goes on with a hop after the latest one's cheer.
    var dressHeldBy: Int?
    var dressHolds = 0
    var holdsDress: Bool { dressHeldBy != nil }
    /// When the hop into my kit is over: a tap before it would stop the change halfway.
    var hopEnds: Date?
    let store: TodayStore
    /// Apple Health, for the home's card and a 训练's chips; nil where the app has none.
    public let health: HealthConnection?
    private let writer: any DisclaimerWriter
    private let posted: @MainActor () -> Void
    private let noSquad: @MainActor (Squad?) -> Void
    let now: () -> Date
    /// Keeps when the latest pat I was shown arrived, so each pat on me plays once, and the night
    /// the lights are on for.
    let defaults: UserDefaults

    /// - Parameters:
    ///   - scene: the squad's scene this week; the gym, the scene the designs are drawn on, until
    ///     the app has read it.
    ///   - posted: called each time a check-in lands, after the payoff starts; the app asks for
    ///     notifications after the first.
    ///   - noSquad: called when a load finds the member in no squad any more, with the squad
    ///     they were in: the captain removed them, or they left on another phone.
    public init(
        store: TodayStore, writer: any DisclaimerWriter, photoSource: PhotoSource = .library,
        scene: SceneTheme = .gym, health: HealthConnection? = nil, now: @escaping () -> Date = Date.init,
        defaults: UserDefaults = .standard,
        bubbleHold: Double? = nil, celebratesTogether: Bool = true, posted: @escaping @MainActor () -> Void,
        noSquad: @escaping @MainActor (Squad?) -> Void = { _ in }
    ) {
        pats = PatStage(bubbleHold: bubbleHold ?? PatStage.bubbleHold)
        together = TogetherStage(isOn: celebratesTogether)
        noticeHold = bubbleHold ?? Motion.noticeHold
        self.scene = scene
        self.defaults = defaults
        self.store = store
        self.health = health
        self.now = now
        self.writer = writer
        self.photoSource = photoSource
        self.posted = posted
        self.noSquad = noSquad
        litNight = defaults.string(forKey: Self.lightsKey)
        // A home loaded under the launch cover stands the squad on the scene from the first frame.
        if store.home == nil { dressMe(hop: false) } else { placeSquad() }
    }

    /// How long after a 练了 the week's count flips up: once the ring closes and the squad cheers.
    private static let scoreDelay = 1.7
    /// The squad's home, with the member's own posts counted.
    public var home: Home? { store.home }
    /// Opens a member's player card with their today over it, from a tap on them (me too).
    @ObservationIgnored public var openTeammate: (MemberID) -> Void = { _ in }
    /// Opens the squad's coach's card, from a tap on it on the sideline; the app sets it.
    @ObservationIgnored public var openCoach: () -> Void = {}
    /// Opens the card of a challenge on its coach's page, from a tap on the coach's head on the
    /// squad card's challenge row; the app sets it.
    @ObservationIgnored public var openChallenge: (DayChallenge) -> Void = { _ in }

    /// The squad dropping onto a newly picked scene (`TodayModel+DropIn.swift`), the tab bar held meanwhile.
    var arrival: Arrival?
    var holdsTabBar = false
    /// A takeover scene's opening, over the whole screen until 进场 (`TodayModel+Opening.swift`).
    var opening: OpeningArt.Loaded?
    /// The squad for the opening's group photo, apart from the home's figures (`+Opening`).
    var openingFigures: [OpeningFigure] = []
    /// The banner on top, over any page, or a celebration's card (on 今天 only), and those waiting.
    var notice: Notice?
    var pendingNotices: [Notice] = []
    /// Refused posts the member was told of and hasn't opened again, oldest first, for 重发.
    var failed: [PendingCheckIn] = []
    public internal(set) var celebration: Broadcast?
    public var isHomeInFront = true
    /// A screen covers the tabs (the editor, a 战报), where a banner would drop in unseen.
    public var isCovered = false
    /// Tells a store or prop the member unlocked (`tellUnlocks(with:)`); nil tells none.
    @ObservationIgnored var unlockNotices: UnlockNotices?
    /// Draws the banner of a notice 通知 was told while the app is open (`tell(_:banner:)`).
    @ObservationIgnored var toldBanner: ((Contracts.Notice) -> AnyView)?
    /// Where a broadcast's banner, or 「还有新通知」, opens its place, as the app routes every notice.
    @ObservationIgnored public var openDestination: ((AppDestination) -> Void)?
    /// Banners shown in a row since the queue was empty, and who hears each from 通知 come on screen.
    @ObservationIgnored var shownInRow = 0
    @ObservationIgnored var bannerShown: [UUID: () -> Void] = [:]
    /// Hears a broadcast opened from its banner's button, so its 通知 row is read.
    @ObservationIgnored public var broadcastOpened: ((Broadcast) -> Void)?

    /// The squad's scene this week, which the app reads with the squad: the gym until then, and
    /// until the squad's first pick. Changing it puts the squad where they belong on the new one.
    public var scene: SceneTheme {
        didSet { if scene != oldValue { placeSquad() } }
    }

    /// The sport a new 练了 starts with, until it is picked from the cover photo.
    var suggestedActivity: Activity { store.suggestedActivity ?? .sport("run") }
    var recentActivities: [Activity] { store.recentActivities }
    /// The squad a post is shared to, unless the member keeps it to themselves.
    var shareSquad: Squad? { store.home?.squad }

    /// Day or night on the scene, on the member's own clock.
    var phase: DayPhase {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return DayPhase(hour: calendar.component(.hour, from: now()))
    }

    var timeZone: TimeZone { store.home?.timeZone ?? .current }

    /// The ring under my feet.
    var myRing: RingStatus {
        StageStatus(training: store.myStatus, activity: nil, plannedRest: home?.mine?.plannedRest ?? false).ring
    }

    /// The week the card shows. Right after my 练了 it keeps the count from before for a moment,
    /// so the number flips up once my ring has closed.
    var cardWeek: (squad: WeekCount, mine: WeekCount)? {
        if let heldWeek { return heldWeek }
        guard let today = home?.today else { return nil }
        return (today.squadWeek, today.myWeek.week)
    }
    private var heldWeek: (squad: WeekCount, mine: WeekCount)?

    /// The night the lights are on for, as `lightsKey` keeps it (`TodayModel+Lights.swift`).
    var litNight: String?
    /// The latest pull of the cord, which the scene plays.
    var lightsPull: LightsPull?
    /// How long my doze lasts after the lights went off: my "z z" come back after it.
    var myDoze = 0.0
    /// My wake-up or doze still waiting for its turn; the next pull cancels it.
    @ObservationIgnored var myLightsMove: Task<Void, Never>?

    /// Puts everyone where they belong after the home changed.
    func placeSquad() {
        // The squad is placed again once it has dropped in.
        guard let home, arrival == nil else { return }
        if let character = home.mine?.character {
            let (look, persona) = (Outfit(character.look), Persona(character.look))
            if look != myLook || persona != myPersona {
                (myLook, myPersona) = (look, persona)
                (player, worn) = (nil, nil)
            }
        }
        if !holdsDress || player == nil { dressMe(hop: false) }
        cast.update(
            home: home, scene: scene, phase: stagePhase, coach: store.coach?.coach, hiring: store.isHiringCoach,
            handover: store.handover)
        if opening != nil { standOpeningSquad() }
    }

    /// A 请假条 is on offer while some day it can count for is free of a 练了 (补打卡).
    var unavailable: Set<CheckInKind> {
        let blocked = blockedForDisclaimer
        return disclaimerDays.contains { !blocked.contains($0) } ? [] : [.disclaimer]
    }

    /// The days a 请假条 can count for, today last.
    var disclaimerDays: [LocalDay] { store.postableDays }

    /// The days a 请假条 can't go on: one with a 练了.
    var blockedForDisclaimer: Set<LocalDay> { store.disclaimerBlockedDays }

    /// The scene blurs behind an open burst. The 请假条 bubble keeps it sharp: the member
    /// writes on the scene itself.
    var isSceneDimmed: Bool { isBurstOpen }

    /// Loads the home, on opening 今天, on coming back to the app, and on a tapped notification.
    public func load() async {
        await store.load()
        showLoaded()
        await health?.refresh()
    }

    /// How often the home is read again while 今天 is on screen, so teammates' posts show up.
    static let rereadEvery = Duration.seconds(60)

    /// Reads the home again while the scene shows nothing in hand: not while a check-in is being
    /// made, the burst is open or the squad is dropping in.
    func reread() async {
        guard step == .scene, !isBurstOpen, arrival == nil else { return }
        await store.refresh()
        showLoaded()
    }

    /// Puts what was loaded on the scene, tells the squad's news, then plays pats on me; or, in
    /// no squad any more, says so.
    private func showLoaded() {
        if store.phase == .noSquad {
            noSquad(store.lostSquad)
            return
        }
        placeSquad()
        Task { await playOpening() }
    }

    /// Opens the check-in kinds, as the 打卡 button does: the 6pm push's 我去发一个 lands here.
    public func openCheckIn() {
        if step == .scene { isBurstOpen = true }
    }

    /// Opens the page for `kind`; a 训练 from the home's card starts from `workout`.
    func pick(_ kind: CheckInKind, workout: ImportedWorkout? = nil) {
        sendFailed = false
        payoff = nil
        // Straight to the page: photos are added there, with its 「+ 照片」 (the 请假条's too).
        compose = newPost(kind, from: workout)
        step = kind == .disclaimer ? .disclaimer : .composing(kind)
    }

    /// The compose page for a post the server refused, with its photos, words, sport, workout and
    /// day as the member made it, to change and send again.
    func resend(_ post: PendingCheckIn) {
        sendFailed = false
        payoff = nil
        let kind = post.draft.kind
        let model = newPost(kind, from: nil)
        model.restore(post)
        compose = model
        step = .composing(kind)
    }

    func cancel() {
        step = .scene
        compose = nil
        sendFailed = false
    }

    func suggestions(for reason: String, style: DisclaimerStyle) async -> DisclaimerSuggestions {
        await writer.suggestions(for: reason, style: style)
    }

    /// Posts `draft` to the squad (or only to me when not `shared`) for `day`, today when left out.
    /// The page closes and the payoff plays once it is queued; it goes out behind the scene
    /// (`deliver`). False when it can never be posted; the open page says so.
    @discardableResult
    func post(_ draft: CheckInDraft, shared: Bool, on day: LocalDay? = nil) async -> Bool {
        guard !isSending else { return false }
        isSending = true
        sendFailed = false
        defer { isSending = false }
        let before = cardWeek
        // A past day's post (补打卡) leaves today's ring and kit as they are.
        let isBackfill = day.map { $0 != store.postableDays.last } ?? false
        let queued: PendingCheckIn
        do {
            queued = try await store.queue(draft, shared: shared, on: day)
        } catch {
            sendFailed = true
            return false
        }
        // Waiting to go out, it counts on the scene now. A 练了's kit goes on after its cheer.
        if draft.kind == .trained, !isBackfill {
            dressHolds += 1
            dressHeldBy = dressHolds
        }
        placeSquad()
        step = .scene
        compose = nil
        land(draft, id: queued.id, weekBefore: before, isBackfill: isBackfill)
        posted()
        deliver(queued.id)
        return true
    }

    /// Stays on the scene: the character celebrates and the line appears over it. The photos stay
    /// in the post, off the scene (the product owner: too busy).
    private func land(
        _ draft: CheckInDraft, id: CheckInID, weekBefore: (squad: WeekCount, mine: WeekCount)?, isBackfill: Bool
    ) {
        let line: String?
        switch draft {
        case .trained(_, _, let body), .healthyMeal(let body), .cheatMeal(let body):
            line = body.caption
        case .disclaimer(let disclaimer, _):
            line = disclaimer.text
        }
        posts += 1
        payoff = Payoff(id: id, kind: draft.kind, line: line)
        // A 请假条 has no cheer; the sleep cap and sign come with their art.
        let cheer =
            draft.kind == .disclaimer
            ? nil
            : try? PlaceholderCharacter.clip(
                "cheer", persona: myPersona, species: PlaceholderCharacter.species(of: myLook))
        // A clip would stop a hop into the kit halfway, in the clothes on screen.
        if let cheer, !isChanging { try? player?.play(cheer) }
        guard draft.kind == .trained, !isBackfill else { return }
        // The big moment: my ring draws and closes, the squad turns and cheers, and only then
        // does the week's count flip up.
        celebrations += 1
        heldWeek = weekBefore
        let phase = stagePhase
        let hold = dressHeldBy
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Motion.ringFill))
            cast.cheerMe(at: phase)
            try? await Task.sleep(for: .seconds(Self.scoreDelay - Motion.ringFill))
            heldWeek = nil
            // Then, the cheer over, I change into the sport's kit and train at it.
            let rest = (cheer?.duration ?? 0) - Self.scoreDelay
            if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
            // A later 练了 holds the kit until its own cheer is over.
            guard dressHeldBy == hold else { return }
            dressHeldBy = nil
            dressMe(hop: true)
        }
    }
}
#endif
