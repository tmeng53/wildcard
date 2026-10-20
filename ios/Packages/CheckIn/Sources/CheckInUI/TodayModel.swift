#if os(iOS)
import AvatarArt
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import Foundation
import Observation
import SwiftUI

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
        case pickingPhotos(Meaning)
        case composing(Meaning)
        case disclaimer
    }

    /// What lands on the scene after a post: the line in the bubble and the pinned cover.
    struct Payoff: Equatable {
        let meaning: Meaning
        let line: String?
        let cover: PreparedPhoto?
    }

    private(set) var board: TodayBoard?
    var isBurstOpen = false
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
    private let service: any CheckInService
    private let writer: any DisclaimerWriter
    private let posted: @MainActor () -> Void

    /// - Parameter posted: called each time a check-in lands, after the payoff starts; the app
    ///   asks for notifications after the first.
    public init(
        service: any CheckInService, writer: any DisclaimerWriter, photoSource: PhotoSource = .library,
        posted: @escaping @MainActor () -> Void
    ) {
        self.service = service
        self.writer = writer
        self.photoSource = photoSource
        self.posted = posted
        player = try? CharacterPlayer(
            figure: PlaceholderCharacter.figure(wearing: Self.look),
            idle: PlaceholderCharacter.clip("idle", persona: Self.persona, species: Self.species))
    }

    /// The member's look and persona; picked at sign-up once onboarding lands.
    private static let look = PlaceholderCharacter.lifter
    private static let persona = Persona.energetic
    /// The lifter's species, whose moves play on top of the persona's.
    private static let species = "person"

    var unavailable: Set<Meaning> {
        (board?.myStatus.allowsDisclaimer ?? true) ? [] : [.disclaimer]
    }

    /// The scene blurs behind an open burst. The 请假条 bubble keeps it sharp: the member
    /// writes on the scene itself.
    var isSceneDimmed: Bool { isBurstOpen }

    /// Reads the board, on opening 今天 and again when a tapped notification brings the member
    /// back to it.
    public func load() async {
        board = try? await service.board()
    }

    func pick(_ meaning: Meaning) {
        sendFailed = false
        payoff = nil
        switch meaning {
        case .disclaimer:
            step = .disclaimer
        case .trained, .healthyMeal, .cheatMeal:
            switch photoSource {
            case .library:
                photos = []
                step = .pickingPhotos(meaning)
            case .provided(let given):
                photos = given
                step = .composing(meaning)
            }
        }
    }

    /// The photo step finished: with photos, or with none (不加照片).
    func photosPicked(_ picked: [PreparedPhoto]) {
        guard case .pickingPhotos(let meaning) = step else { return }
        photos = Array(picked.prefix(Photos.maxCount))
        step = .composing(meaning)
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
        do {
            let updated = try await service.post(draft)
            step = .scene
            photos = []
            land(draft)
            board = updated
            posted()
        } catch {
            sendFailed = true
        }
    }

    /// Stays on the scene: the character celebrates, the line and cover appear beside it.
    private func land(_ draft: CheckInDraft) {
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
        payoff = Payoff(meaning: draft.meaning, line: line, cover: cover)
        // A 请假条 has no cheer; the sleep cap and sign come with their art.
        if draft.meaning != .disclaimer,
            let cheer = try? PlaceholderCharacter.clip("cheer", persona: Self.persona, species: Self.species)
        {
            try? player?.play(cheer)
        }
    }
}
#endif
