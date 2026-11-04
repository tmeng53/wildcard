#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarUI
import CharacterEditorDomain
import Contracts
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
            restyle(move: nil)
        }
    }
    /// The store open on the 穿搭 tab; nil shows the shopping street.
    private(set) var store: String?
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

    public init(
        draft: CharacterDraft, tab: EditorTab = .look, arrived: Set<String> = [],
        marks: any WardrobeMarks = MemoryWardrobeMarks()
    ) {
        self.draft = draft
        self.tab = tab
        self.marks = marks
        (opened, seen) = (marks.opened, marks.seen)
        // A piece the look already wears was found before boxes came in; it needs no opening.
        let worn = Set(draft.picks.variants.values)
        self.arrived = arrived.filter { piece in
            draft.catalog.storeOf[piece] != nil && !worn.contains(piece)
        }
    }

    /// The placeholder character's catalog, with the stores and props the member unlocked open,
    /// and a look to start from: the one given, or a random one until sign-up hands over the last
    /// look its first screen showed.
    public static func placeholder(
        look: Outfit? = nil, persona: Persona = .energetic, nickname: String, tab: EditorTab = .look,
        unlocks: [Unlock] = [], locked: [LockedPiece] = [], marks: any WardrobeMarks = MemoryWardrobeMarks()
    ) throws(AvatarError) -> CharacterEditorModel {
        let catalog = try Catalog.placeholder(unlocks: unlocks, locked: locked)
        var generator = SystemRandomNumberGenerator()
        let start = look ?? CharacterDraft.randomLook(from: catalog, using: &generator)
        return CharacterEditorModel(
            draft: CharacterDraft(catalog: catalog, look: start, persona: persona, nickname: nickname), tab: tab,
            arrived: Set(unlocks.filter { $0.kind == .piece }.map(\.id)), marks: marks)
    }

    /// Locks `pieces` in an editor opened before they were known, as sign-up's first screen is,
    /// for a member who has unlocked nothing yet: they become boxes, and a locked piece the look
    /// wears goes back to what the rig draws there. Undo starts over.
    public func lock(_ pieces: [LockedPiece]) throws(AvatarError) {
        guard !pieces.isEmpty else { return }
        let catalog = try Catalog.placeholder(locked: pieces)
        var look = draft.picks
        for (slot, locked) in catalog.locked {
            guard let worn = look.variants[slot], locked[worn] != nil else { continue }
            look.variants[slot] = catalog.defaults[slot]
            look.colors[slot] = nil
        }
        draft = CharacterDraft(catalog: catalog, look: look, persona: draft.persona, nickname: draft.nickname)
        (store, picked, arrival) = (nil, nil, nil)
        if player != nil { restyle(move: nil) }
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

    /// Walks into an open store; a closed one stays shut, its card saying how it unlocks.
    func visit(_ store: EditorChoices.Store) {
        guard store.isOpen else { return }
        (self.store, picked) = (store.id, nil)
    }

    /// Opens on what a 练了 just unlocked, from its notice on the home or in 通知: inside the store on
    /// the 穿搭 tab, or on the 道具 tab for a prop. New pieces wait in their 「？」 boxes in a pop-up
    /// over the editor, every one this phone hasn't opened, which tells only which store they came
    /// to, until the member opens them all at once or not.
    public func show(_ unlock: Unlock) {
        show(unlock.kind, item: unlock.id)
    }

    /// `show(_:)` by what unlocked, as 通知 names it.
    public func show(_ kind: Unlock.Kind, item: String) {
        switch kind {
        case .store:
            guard let store = draft.catalog.stores.first(where: { $0.id == item && $0.isOpen }) else { return }
            tab = .outfit
            visit(store)
        case .prop:
            tab = .prop
        case .piece:
            tab = .outfit
            showArrivals()
        }
    }

    /// The pieces that came in that this phone hasn't opened, on the racks of open stores, in
    /// street order: they hang as boxes 「可以开了」 until opened.
    var unopened: [String] {
        let open = draft.catalog.stores.filter(\.isOpen).map(\.id)
        return open.flatMap { store in
            draft.catalog.rack(of: store).map(\.variant).filter { arrived.contains($0) && !opened.contains($0) }
        }
    }

    /// Whether the piece came in and still waits in its box.
    func isBoxed(_ piece: String) -> Bool { arrived.contains(piece) && !opened.contains(piece) }

    /// Whether the piece was opened here and not tapped since: it wears NEW.
    func isNew(_ piece: String) -> Bool { opened.contains(piece) && arrived.contains(piece) && !seen.contains(piece) }

    /// Whether the store has a piece waiting in its box or wearing NEW, for its card on the street.
    func hasNews(_ store: String) -> Bool {
        draft.catalog.rack(of: store).contains { isBoxed($0.variant) || isNew($0.variant) }
    }

    /// The boxes waiting, in the pop-up the editor opens with.
    struct Arrival: Equatable {
        let pieces: [String]
        /// The one store they all came to, or nil when they came to several.
        let store: String?
    }

    /// The boxes waiting in the pop-up, until the member opens them or leaves them.
    private(set) var arrival: Arrival?

    /// Puts the pop-up up with every box this phone hasn't opened, if any.
    func showArrivals() {
        let pieces = unopened
        guard !pieces.isEmpty else { return }
        let stores = Set(pieces.compactMap { draft.catalog.storeOf[$0] })
        arrival = Arrival(pieces: pieces, store: stores.count == 1 ? stores.first : nil)
    }

    /// 一键全开, once the boxes' opening has played: every box opens, each piece wears NEW on its
    /// rack, and the shopping street shows, each store with news marked. Nothing is put on.
    func openArrival() {
        guard let arrival else { return }
        self.arrival = nil
        marks.open(Set(arrival.pieces))
        opened = marks.opened
        (store, picked) = (nil, nil)
    }

    /// 先不了: the boxes stay on their racks, 「可以开了」, and open the pop-up again when tapped.
    func leaveArrival() {
        arrival = nil
    }

    /// A piece on a rack, its slot and the draft wearing it, so its picture shows in the colors
    /// it would be worn in.
    func preview(of piece: String) -> (slot: Slot, outfit: Outfit)? {
        guard let store = draft.catalog.storeOf[piece],
            let slot = draft.catalog.rack(of: store).first(where: { $0.variant == piece })?.slot
        else { return nil }
        var wearing = draft
        wearing.pick(piece, for: slot)
        return (slot, wearing.outfit)
    }

    @ObservationIgnored private let marks: any WardrobeMarks
    /// The pieces the member unlocked that hang on a rack this build has.
    private let arrived: Set<String>
    private var opened: Set<String>
    private var seen: Set<String>

    /// Back out to the shopping street.
    func leaveStore() {
        (store, picked) = (nil, nil)
    }

    /// Puts on a piece from the open store's rack; a second tap takes off a hat or an accessory,
    /// which a look can go without.
    func pickFromRack(_ variant: String, for slot: Slot) {
        if isNew(variant) {
            marks.see(variant)
            seen = marks.seen
        }
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

    /// Back to 长相 when the character became an animal on 发型 or 脸, which it no longer has.
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
