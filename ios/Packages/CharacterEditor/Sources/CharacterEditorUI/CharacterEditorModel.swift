#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarUI
import CharacterEditorDomain
import Foundation
import Observation

/// The editor's tabs, in order. 发型 and 脸 show only while the character is a person.
public enum EditorTab: String, CaseIterable, Hashable, Sendable {
    case look, hair, face, outfit, prop, persona

    /// Whether the tab dresses a person only: an animal's face and coat come together.
    var isForPeople: Bool { self == .hair || self == .face }
}

/// The one move a change plays: the look's (the held prop's move, else the persona's cheer),
/// or the persona's cheer when the persona changes.
private enum StageMove {
    case look, cheer
}

/// Where the editor is open: as a step of sign-up, or from 我 to change the character.
public enum EditorContext: Hashable, Sendable {
    case signUp(step: Int, total: Int)
    case profile
}

/// What the editor hands back when the person is done.
public struct EditedCharacter: Hashable, Sendable {
    public let outfit: Outfit
    public let persona: Persona
    public let nickname: String
}

/// The editor's state on screen: the draft, the open tab and the character playing on the
/// stage. While the person dresses the character it stands still, and every change plays one
/// move: the held prop's own (a dumbbell's lift, a racket's swing), else the persona's cheer.
/// On the 性格 tab it plays the persona's idle, so the persona shows; picking a persona plays
/// its cheer, and a held prop gets its move again after `propEvery` idle seconds.
@MainActor @Observable
public final class CharacterEditorModel {
    public private(set) var draft: CharacterDraft
    public var tab: EditorTab {
        didSet {
            guard tab != oldValue else { return }
            // The 性格 tab counts its idle seconds from when it opens.
            if tab == .persona { moveEnds = .now }
            knocked = nil
            restyle(move: nil)
        }
    }
    /// The store open on the 穿搭 tab; nil shows the shopping street.
    private(set) var store: String?
    /// A closed store tapped on the street, whose opening line shows under it.
    private(set) var knocked: String?
    /// The slot of the piece last picked off the open store's rack, whose colors show over it.
    private(set) var picked: Slot?
    /// Nil until the first figure is built.
    public private(set) var player: CharacterPlayer?
    /// Thumbnails of the tiles, kept while the editor is open.
    let thumbnails = ThumbnailCache()
    /// Bumped by every change, so a slower figure build never replaces a newer look.
    @ObservationIgnored private var request = 0
    @ObservationIgnored private var clips: [String: Clip] = [:]
    @ObservationIgnored private var propMoves: [String: Clip?] = [:]
    @ObservationIgnored private var outfitOnStage: Outfit?
    /// When the last one-off move ends, from which the 性格 tab counts its idle seconds.
    @ObservationIgnored private(set) var moveEnds = Date.distantPast

    /// Idle seconds on the 性格 tab before a held prop plays its move again.
    static let propEvery: Double = 12

    public init(draft: CharacterDraft, tab: EditorTab = .look) {
        self.draft = draft
        self.tab = tab
    }

    /// The placeholder character's catalog and a look to start from: the one given, or a random
    /// one until sign-up hands over the last look its first screen showed.
    public static func placeholder(
        look: Outfit? = nil, persona: Persona = .energetic, nickname: String, tab: EditorTab = .look
    ) throws(AvatarError) -> CharacterEditorModel {
        let catalog = try Catalog.placeholder()
        var generator = SystemRandomNumberGenerator()
        let start = look ?? CharacterDraft.randomLook(from: catalog, using: &generator)
        return CharacterEditorModel(
            draft: CharacterDraft(catalog: catalog, look: start, persona: persona, nickname: nickname), tab: tab)
    }

    /// A fixed look for screenshots and UI tests: a person with a bob, a tee, shorts and a
    /// dumbbell.
    public static let sampleLook = PlaceholderCharacter.lifter

    public var tabs: [EditorTab] {
        EditorTab.allCases.filter { !$0.isForPeople || draft.wearsHair }
    }

    /// The field keeps what is typed, so pinyin still being composed is never cut; a name
    /// longer than the limit just can't be saved.
    public var nickname: String {
        get { draft.nickname }
        set { draft.nickname = newValue }
    }

    /// What to save, once the nickname is a valid one.
    public var result: EditedCharacter? {
        draft.name.map { EditedCharacter(outfit: draft.outfit, persona: draft.persona, nickname: $0) }
    }

    /// Builds the first figure. The stage stays empty for the moment this takes.
    func start() {
        guard player == nil else { return }
        restyle(move: nil)
    }

    func pick(_ variant: String?, for slot: Slot) {
        guard draft.pick(variant, for: slot) else { return }
        leaveTabsForPeople()
        restyle(move: .look)
    }

    /// Walks into an open store, or tells how a closed one opens.
    func visit(_ store: EditorChoices.Store) {
        guard store.isOpen else {
            knocked = store.id
            return
        }
        (self.store, knocked, picked) = (store.id, nil, nil)
    }

    /// Back out to the shopping street.
    func leaveStore() {
        (store, picked) = (nil, nil)
    }

    /// Puts on a piece from the open store's rack; a second tap takes off a hat or an accessory,
    /// which a look can go without.
    func pickFromRack(_ variant: String, for slot: Slot) {
        let takesOff = Self.optionalClothes.contains(slot) && draft.picks.variants[slot] == variant
        pick(takesOff ? nil : variant, for: slot)
        picked = takesOff ? nil : slot
    }

    /// The clothes a look can go without.
    static let optionalClothes: Set<Slot> = ["hat", "acc"]

    func pickColor(_ color: RGBAColor?, for slot: Slot) {
        guard draft.pickColor(color, for: slot) else { return }
        restyle(move: .look)
    }

    func choose(_ persona: Persona) {
        guard draft.choose(persona) else { return }
        restyle(move: .cheer)
    }

    func undo() {
        guard draft.undo() else { return }
        leaveTabsForPeople()
        restyle(move: .look)
    }

    func shuffle() {
        var generator = SystemRandomNumberGenerator()
        draft.shuffle(using: &generator)
        leaveTabsForPeople()
        restyle(move: .look)
    }

    /// Back to 样子 when the character became an animal on 发型 or 脸, which it no longer has.
    private func leaveTabsForPeople() {
        if tab.isForPeople && !draft.wearsHair { tab = .look }
    }

    /// The persona's cheer, for a tap on the character.
    func cheer() {
        guard let cheer = clip("cheer") else { return }
        play(cheer)
    }

    /// The held prop's move, once the character has stood idle on the 性格 tab for
    /// `propEvery` seconds since its last move; the stage calls it while that tab is open.
    func propMoveIfIdle(now: Date = .now) {
        guard tab == .persona, now >= moveEnds.addingTimeInterval(Self.propEvery),
            let move = propMove()
        else { return }
        play(move, now: now)
    }

    /// The persona one step along, for a swipe across the stage on the 性格 tab.
    func choosePersona(after step: Int) {
        let all = Persona.allCases
        guard let index = all.firstIndex(of: draft.persona) else { return }
        let next = index + step
        guard all.indices.contains(next) else { return }
        choose(all[next])
    }

    /// Dresses the stage in the draft's outfit and idle, then plays one move if asked. The
    /// figure is built off the main actor, since it reads and parses art.
    private func restyle(move: StageMove?) {
        request += 1
        let ticket = request
        let outfit = draft.outfit
        // A new persona or tab keeps the figure on stage; only new clothes need a new one.
        if let player, outfitOnStage == outfit {
            show(player.figure, wearing: outfit, ticket: ticket, move: move)
            return
        }
        Task {
            guard let figure = try? await Self.figure(wearing: outfit) else { return }
            self.show(figure, wearing: outfit, ticket: ticket, move: move)
        }
    }

    private func show(_ figure: Figure, wearing outfit: Outfit, ticket: Int, move: StageMove?) {
        guard ticket == request else { return }
        outfitOnStage = outfit
        let idle = (tab == .persona ? clip("idle") : nil) ?? .still
        if let player {
            try? player.wear(figure, idle: idle)
        } else {
            player = try? CharacterPlayer(figure: figure, idle: idle)
        }
        let chosen: Clip? =
            switch move {
            case .look?: propMove() ?? clip("cheer")
            case .cheer?: clip("cheer")
            case nil: nil
            }
        if let chosen { play(chosen) }
    }

    private func play(_ clip: Clip, now: Date = .now) {
        guard let player else { return }
        do {
            try player.play(clip, now: now)
            moveEnds = now.addingTimeInterval(clip.duration)
        } catch {
            // A clip that doesn't fit the figure plays nothing; the character stays as it was.
        }
    }

    /// The move of the prop the draft holds, if it has one.
    private func propMove() -> Clip? {
        let outfit = draft.outfit
        let prop = outfit.variants["prop"] ?? ""
        if let cached = propMoves[prop] { return cached }
        let move = try? PlaceholderCharacter.propMove(for: outfit)
        propMoves[prop] = move
        return move
    }

    /// The persona's clip with the moves of the draft's species on top.
    private func clip(_ name: String) -> Clip? {
        let species = draft.outfit.variants["body"].flatMap(draft.catalog.species(of:))?.id
        let key = "\(draft.persona.rawValue)/\(name)/\(species ?? "")"
        if let clip = clips[key] { return clip }
        let clip = try? PlaceholderCharacter.clip(name, persona: draft.persona, species: species)
        clips[key] = clip
        return clip
    }

    /// Reads and parses the art for an outfit away from the main actor.
    nonisolated static func figure(wearing outfit: Outfit) async throws -> Figure {
        try await Task.detached(priority: .userInitiated) {
            try PlaceholderCharacter.figure(wearing: outfit)
        }.value
    }
}
#endif
