#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import Foundation
import Observation
import SwiftUI

extension CheckInDraft {
    var kind: CheckInKind {
        switch self {
        case .trained: .trained
        case .healthyMeal: .healthyMeal
        case .cheatMeal: .cheatMeal
        case .disclaimer: .disclaimer
        }
    }
}

/// Where photos for a 练了 or a meal come from.
public enum PhotoSource: Sendable {
    /// The system photo picker.
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
        case pickingPhotos(CheckInKind)
        case composing(CheckInKind)
        case disclaimer
    }

    /// What lands on the scene after a post: the line in the bubble, and the post it opens once
    /// the server saved it.
    struct Payoff: Equatable {
        let kind: CheckInKind
        let line: String?
        let post: CheckIn?
    }

    /// Opening it closes a teammate's bubble, which would otherwise stay sharp over the blur.
    var isBurstOpen = false {
        didSet { if isBurstOpen { pats.dismissBubble() } }
    }
    /// Everyone else on the scene.
    let cast = SquadCast()
    /// 拍一拍 on the scene.
    let pats = PatStage()
    /// Bumps on each of my 练了: the ring under my feet draws, the squad cheers, the streamers fall.
    private(set) var celebrations = 0
    private(set) var step = Step.scene

    /// Whether the app's tab bar shows: on the scene, but not while the 打卡 burst is open (a tap
    /// anywhere outside its capsules closes it) or a check-in is being written (the compose and
    /// 请假条 pages take the whole screen).
    public var showsTabBar: Bool {
        switch step {
        case .scene, .pickingPhotos: !isBurstOpen
        case .composing, .disclaimer: false
        }
    }

    /// The photos picked for the open compose step, the cover first.
    var photos: [PreparedPhoto] = []
    private(set) var payoff: Payoff?
    /// Counts posts, so the one strong haptic fires on each.
    private(set) var posts = 0
    private(set) var isSending = false
    /// The last post didn't go out; the open step says so and can try again.
    private(set) var sendFailed = false

    let photoSource: PhotoSource
    /// My character, as I made it once the home says so; the stand-in lifter until then.
    private(set) var player: CharacterPlayer?
    private var myLook = PlaceholderCharacter.lifter
    private var myPersona = Persona.energetic
    private let store: TodayStore
    private let writer: any DisclaimerWriter
    private let posted: @MainActor () -> Void

    let now: () -> Date
    /// Keeps when the latest pat I was shown arrived, so each pat on me plays once.
    private let defaults: UserDefaults

    /// - Parameters:
    ///   - scene: the squad's scene this week; the gym, the scene the designs are drawn on, until
    ///     the app has read it.
    ///   - posted: called each time a check-in lands, after the payoff starts; the app asks for
    ///     notifications after the first.
    public init(
        store: TodayStore, writer: any DisclaimerWriter, photoSource: PhotoSource = .library,
        scene: SceneTheme = .gym, now: @escaping () -> Date = Date.init, defaults: UserDefaults = .standard,
        posted: @escaping @MainActor () -> Void
    ) {
        self.scene = scene
        self.defaults = defaults
        self.store = store
        self.now = now
        self.writer = writer
        self.photoSource = photoSource
        self.posted = posted
        player = Self.player(wearing: myLook, persona: myPersona)
    }

    private static func player(wearing look: Outfit, persona: Persona) -> CharacterPlayer? {
        try? CharacterPlayer(
            figure: PlaceholderCharacter.figure(wearing: look),
            idle: PlaceholderCharacter.clip("idle", persona: persona, species: PlaceholderCharacter.species(of: look)))
    }

    /// How long after posting a 练了 the week's count flips up: after the ring closes and the
    /// squad starts cheering (the approved check-in moment's 1.7 seconds).
    private static let scoreDelay = 1.7

    /// The squad's home, with the member's own posts counted.
    var home: Home? { store.home }

    /// The squad dropping onto a newly picked scene, from `dropIn(on:)` until everyone has
    /// settled (`TodayModel+DropIn.swift`).
    var arrival: Arrival?

    /// The squad's scene this week, which the app reads with the squad: the gym until then, and
    /// until the squad's first pick. Changing it puts the squad where they belong on the new one.
    public var scene: SceneTheme {
        didSet { if scene != oldValue { placeSquad() } }
    }

    /// The sport a new 练了 starts with, until it is picked from the cover photo.
    var suggestedActivity: Activity { store.suggestedActivity ?? .sport("run") }

    /// Day or night on the scene, on the member's own clock.
    var phase: DayPhase {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = store.home?.timeZone ?? .current
        return DayPhase(hour: calendar.component(.hour, from: now()))
    }

    /// 今日赛况, from 21:00 on the member's own clock until their day ends; nil before.
    var recap: DayRecap? {
        guard let home, home.showsRecap(at: now()) else { return nil }
        return home.recap(pending: store.pending)
    }

    /// Noon of the member's today in their time zone: the day the recap's title names.
    var dayDate: Date? {
        guard let home, let day = home.mine?.day else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = home.timeZone
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
    }

    /// A member's head and name on 今日赛况: 我 for me, else their nickname, or 队友 before they
    /// made their character.
    func recapMember(_ member: MemberID) -> (head: CharacterPlayer?, name: String) {
        if member == home?.member { return (player, String(localized: "我", bundle: .module)) }
        let nickname = home?.today.members.first { $0.member == member }?.character?.nickname.text
        return (head(of: member.description), nickname ?? String(localized: "队友", bundle: .module))
    }

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

    /// The character whose head the card shows for a member (`MemberID`'s description).
    func head(of member: String) -> CharacterPlayer? {
        guard member != home?.member.description else { return player }
        return cast.mates.first { $0.id.description == member }?.player
    }

    /// Puts everyone where they belong after the home changed.
    func placeSquad() {
        // The squad is placed again once it has dropped in.
        guard let home, arrival == nil else { return }
        if let character = home.mine?.character {
            let (look, persona) = (Outfit(character.look), Persona(character.look))
            if look != myLook || persona != myPersona {
                (myLook, myPersona) = (look, persona)
                player = Self.player(wearing: look, persona: persona)
            }
        }
        cast.update(home: home, scene: scene, phase: phase)
    }

    var unavailable: Set<CheckInKind> {
        store.myStatus.allowsDisclaimer ? [] : [.disclaimer]
    }

    /// The scene blurs behind an open burst. The 请假条 bubble keeps it sharp: the member
    /// writes on the scene itself.
    var isSceneDimmed: Bool { isBurstOpen }

    /// Loads the home, on opening 今天, on coming back to the app, and when a tapped
    /// notification brings the member back to it.
    public func load() async {
        await store.load()
        placeSquad()
        Task { await playPatsOnMe() }
    }

    // MARK: 拍一拍

    /// A teammate on the scene was tapped: their status and 「拍一拍」.
    func tapMate(_ id: MemberID) {
        guard let mate = cast.mates.first(where: { $0.id == id }) else { return }
        pats.tap(mate, cast: cast, phase: phase)
    }

    /// Whether I can still pat `id` today.
    func canPat(_ id: MemberID) -> Bool {
        store.canPat(id)
    }

    /// I pat a teammate from their bubble: it plays at once and goes to the server, once a day.
    func patMate(_ id: MemberID) {
        guard store.canPat(id), let mate = cast.mates.first(where: { $0.id == id }) else { return }
        guard pats.pat(mate, mine: player) else { return }
        Task { try? await store.pat(id) }
    }

    /// The key under which the latest pat already shown to `member` is kept, apart for each
    /// account signed in on this phone.
    private static func patsShownKey(for member: MemberID) -> String {
        "today.patsShownUntil.\(member)"
    }

    /// Whoever patted me since the last pat shown pats me now, from where they stand: the
    /// earliest, with the next one named on their bubble. Each pat plays once on this phone.
    private func playPatsOnMe() async {
        guard let member = store.home?.member else { return }
        let shown = defaults.double(forKey: Self.patsShownKey(for: member))
        let fresh = store.pokes.received.filter { Double($0.patAt.millisecondsSince1970) > shown }
        let patters = fresh.compactMap { pat in cast.mates.first { $0.id == pat.from } }
        guard let latest = fresh.last, let first = patters.first else { return }
        try? await Task.sleep(for: .seconds(PatStage.patMeDelay))
        await untilArrived()
        guard pats.patMe(by: first, others: Array(patters.dropFirst()), mine: player, myPersona: myPersona)
        else { return }
        defaults.set(Double(latest.patAt.millisecondsSince1970), forKey: Self.patsShownKey(for: member))
    }

    func pick(_ kind: CheckInKind) {
        sendFailed = false
        payoff = nil
        switch kind {
        case .disclaimer:
            step = .disclaimer
        case .trained, .healthyMeal, .cheatMeal:
            switch photoSource {
            case .library:
                photos = []
                step = .pickingPhotos(kind)
            case .provided(let given):
                photos = given
                step = .composing(kind)
            }
        }
    }

    /// The photo step finished: with photos, or with none (不加照片).
    func photosPicked(_ picked: [PreparedPhoto]) {
        guard case .pickingPhotos(let kind) = step else { return }
        photos = Array(picked.prefix(Photos.maxCount))
        step = .composing(kind)
    }

    /// Moves `photo` to the front, as the cover.
    func makeCover(_ photo: PreparedPhoto) {
        guard let index = photos.firstIndex(of: photo) else { return }
        photos.insert(photos.remove(at: index), at: 0)
    }

    func cancel() {
        step = .scene
        photos = []
        sendFailed = false
    }

    func suggestions(for reason: String, style: DisclaimerStyle) async -> DisclaimerSuggestions {
        await writer.suggestions(for: reason, style: style)
    }

    func post(_ draft: CheckInDraft) async {
        guard !isSending else { return }
        isSending = true
        sendFailed = false
        defer { isSending = false }
        let before = cardWeek
        do {
            // Posted or waiting to go out, it counts on the scene now.
            let outcome = try await store.post(draft)
            placeSquad()
            step = .scene
            photos = []
            land(draft, weekBefore: before, saved: outcome)
            posted()
        } catch {
            sendFailed = true
        }
    }

    /// Stays on the scene: the character celebrates and the line appears over it. The photos stay
    /// in the post, off the scene (the product owner: too busy).
    private func land(
        _ draft: CheckInDraft, weekBefore: (squad: WeekCount, mine: WeekCount)?, saved: TodayStore.PostOutcome
    ) {
        let line: String?
        switch draft {
        case .trained(_, _, let body), .healthyMeal(let body), .cheatMeal(let body):
            line = body.caption
        case .disclaimer(let disclaimer):
            line = disclaimer.text
        }
        posts += 1
        let post: CheckIn? = if case .posted(let checkIn) = saved { checkIn } else { nil }
        payoff = Payoff(kind: draft.kind, line: line, post: post)
        // A 请假条 has no cheer; the sleep cap and sign come with their art.
        if draft.kind != .disclaimer,
            let cheer = try? PlaceholderCharacter.clip(
                "cheer", persona: myPersona, species: PlaceholderCharacter.species(of: myLook))
        {
            try? player?.play(cheer)
        }
        guard draft.kind == .trained else { return }
        // The big moment: my ring draws and closes, the squad turns and cheers, and only then
        // does the week's count flip up.
        celebrations += 1
        heldWeek = weekBefore
        let phase = phase
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Motion.ringFill))
            cast.cheerMe(at: phase)
            try? await Task.sleep(for: .seconds(Self.scoreDelay - Motion.ringFill))
            heldWeek = nil
        }
    }
}
#endif
