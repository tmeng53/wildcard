#if os(iOS)
import AvatarArt
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

    /// What lands on the scene after a post: the line in the bubble and the pinned cover.
    struct Payoff: Equatable {
        let kind: CheckInKind
        let line: String?
        let cover: PreparedPhoto?
    }

    var isBurstOpen = false
    /// Everyone else on the scene.
    let cast = SquadCast()
    /// Bumps on each of my 练了: the ring under my feet draws, the squad cheers, the streamers fall.
    private(set) var celebrations = 0
    private(set) var step = Step.scene
    /// The photos picked for the open compose step, the cover first.
    var photos: [PreparedPhoto] = []
    private(set) var payoff: Payoff?
    /// Counts posts, so the one strong haptic fires on each.
    private(set) var posts = 0
    private(set) var isSending = false
    /// The last post didn't go out; the open step says so and can try again.
    private(set) var sendFailed = false

    let photoSource: PhotoSource
    let player: CharacterPlayer?
    private let store: TodayStore
    private let writer: any DisclaimerWriter

    private let now: () -> Date

    public init(
        store: TodayStore, writer: any DisclaimerWriter, photoSource: PhotoSource = .library,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
        self.writer = writer
        self.photoSource = photoSource
        player = try? CharacterPlayer(
            figure: PlaceholderCharacter.figure(wearing: Self.look),
            idle: PlaceholderCharacter.clip("idle", persona: Self.persona, species: Self.species))
    }

    /// The member's look and persona; picked at sign-up once onboarding lands.
    private static let look = PlaceholderCharacter.lifter
    private static let persona = Persona.energetic
    /// The lifter's species, whose moves play on top of the persona's.
    private static let species = "person"

    /// How long after posting a 练了 the week's count flips up: after the ring closes and the
    /// squad starts cheering (the approved check-in moment's 1.7 seconds).
    private static let scoreDelay = 1.7

    /// Each squad picks its scene once squad settings land; 跑道 until then.
    private static let scene = SceneTheme.track

    /// The squad's home, with the member's own posts counted.
    var home: Home? { store.home }

    /// The squad's scene.
    var scene: SceneTheme { Self.scene }

    /// The sport a new 练了 starts with, until it is picked from the cover photo.
    var suggestedActivity: Activity { store.suggestedActivity ?? .sport(.run) }

    /// Day or night on the scene, on the member's own clock.
    var phase: DayPhase {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = store.home?.timeZone ?? .current
        return DayPhase(hour: calendar.component(.hour, from: now()))
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
        guard let home else { return }
        cast.update(home: home, scene: scene, phase: phase)
    }

    var unavailable: Set<CheckInKind> {
        store.myStatus.allowsDisclaimer ? [] : [.disclaimer]
    }

    /// The scene blurs behind an open burst. The 请假条 bubble keeps it sharp: the member
    /// writes on the scene itself.
    var isSceneDimmed: Bool { isBurstOpen }

    func load() async {
        await store.load()
        placeSquad()
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
            try await store.post(draft)
            placeSquad()
            step = .scene
            photos = []
            land(draft, weekBefore: before)
        } catch {
            sendFailed = true
        }
    }

    /// Stays on the scene: the character celebrates, the line and cover appear beside it.
    private func land(_ draft: CheckInDraft, weekBefore: (squad: WeekCount, mine: WeekCount)?) {
        let line: String?
        let cover: PreparedPhoto?
        switch draft {
        case .trained(_, let body), .healthyMeal(let body), .cheatMeal(let body):
            line = body.caption
            cover = body.cover
        case .disclaimer(let disclaimer):
            line = disclaimer.text
            cover = nil
        }
        posts += 1
        payoff = Payoff(kind: draft.kind, line: line, cover: cover)
        // A 请假条 has no cheer; the sleep cap and sign come with their art.
        if draft.kind != .disclaimer,
            let cheer = try? PlaceholderCharacter.clip("cheer", persona: Self.persona, species: Self.species)
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
