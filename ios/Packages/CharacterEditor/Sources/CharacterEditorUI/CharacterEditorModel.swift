#if os(iOS)
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
    /// The slot of the piece last picked in the wardrobe (穿搭), whose colors show over it.
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
        draft: CharacterDraft, tab: EditorTab = .look, arrived: Set<String> = [], claimed: Set<String> = [],
        marks: any WardrobeMarks = MemoryWardrobeMarks()
    ) {
        self.draft = draft
        self.tab = tab
        self.marks = marks
        seen = marks.seen
        // A piece the look already wears was found before 领取 came in; it is the member's.
        let worn = Set(draft.picks.variants.values)
        self.arrived = arrived.subtracting(worn)
        self.claimed = claimed
    }

    /// The placeholder character's catalog on the member's 商店街 (`stock`; the starter street
    /// while it isn't known) with the props they unlocked, and a look to start from: the one
    /// given, or a random one until sign-up hands over the last look its first screen showed. The
    /// wardrobe (穿搭) holds the pieces of open stores that came with them and the unlocked pieces
    /// in `claimed`.
    public static func placeholder(
        look: Outfit? = nil, persona: Persona = .energetic, nickname: String, tab: EditorTab = .look,
        unlocks: [Unlock] = [], stock: StreetStock? = nil, claimed: Set<String> = [],
        marks: any WardrobeMarks = MemoryWardrobeMarks()
    ) throws(AvatarError) -> CharacterEditorModel {
        let catalog = try Catalog.placeholder(unlocks: unlocks, stock: stock)
        var generator = SystemRandomNumberGenerator()
        let start = look ?? CharacterDraft.randomLook(from: catalog, using: &generator)
        return CharacterEditorModel(
            draft: CharacterDraft(catalog: catalog, look: start, persona: persona, nickname: nickname), tab: tab,
            arrived: Set(unlocks.filter { $0.kind == .piece }.map(\.id)), claimed: claimed, marks: marks)
    }

    /// Puts the member's own 商店街 in an editor opened before it was known, as sign-up's first
    /// screen is, for a member who has unlocked nothing yet: a piece the look wears that the street
    /// doesn't offer goes back to what the rig draws there. Undo starts over.
    public func stock(_ stock: StreetStock) throws(AvatarError) {
        let catalog = try Catalog.placeholder(stock: stock)
        var look = draft.picks
        for slot in Catalog.clothingSlots {
            guard let worn = look.variants[slot], worn != catalog.defaults[slot],
                !(catalog.variants[slot] ?? []).contains(worn)
            else { continue }
            look.variants[slot] = catalog.defaults[slot]
            look.colors[slot] = nil
        }
        draft = CharacterDraft(catalog: catalog, look: look, persona: draft.persona, nickname: draft.nickname)
        picked = nil
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

    /// Opens on a prop the member's training unlocked, from its notice: the 道具 tab. Stores and
    /// pieces open on 商店街 (`StreetModel`).
    public func show(_ kind: Unlock.Kind, item: String) {
        if kind == .prop { tab = .prop }
    }

    /// Opens on the wardrobe wearing `piece`, as 商店街's 「穿上看看」 and its owned pieces ask. It is
    /// only the draft's, so leaving without saving keeps the look the member had.
    public func tryOn(_ piece: String) {
        tab = .outfit
        guard let slot = wardrobe.first(where: { $0.pieces.contains(piece) })?.slot else { return }
        // Already worn, it isn't put on again (a second tap takes it off), but its slot still shows.
        guard draft.picks.variants[slot] != piece else {
            picked = slot
            return
        }
        wear(piece, for: slot)
    }

    /// 我的衣橱: what the member owns, by slot in the art's order, every slot even when empty: every piece of the open stores but
    /// the unlocked ones not claimed yet, which wait on 商店街.
    var wardrobe: [(slot: Slot, pieces: [String])] {
        let catalog = draft.catalog
        let open = catalog.stores.filter(\.isOpen).map(\.id)
        let racks = open.flatMap { catalog.rack(of: $0) }.filter { owns($0.variant) }
        // Every slot, an empty one too: its tab says it's still empty (Tracy 2026-11-05).
        return Catalog.clothingSlots.map { slot in
            (slot, racks.filter { $0.slot == slot }.map(\.variant))
        }
    }

    private func owns(_ piece: String) -> Bool { !arrived.contains(piece) || claimed.contains(piece) }

    /// Whether a claimed piece hasn't been tapped in the wardrobe yet: it wears NEW.
    func isNew(_ piece: String) -> Bool { arrived.contains(piece) && claimed.contains(piece) && !seen.contains(piece) }

    @ObservationIgnored private let marks: any WardrobeMarks
    /// The pieces the member unlocked, which are theirs once claimed.
    private let arrived: Set<String>
    private let claimed: Set<String>
    private var seen: Set<String>

    /// Puts on a piece from the wardrobe; a second tap takes off a hat or an accessory, which a look
    /// can go without.
    func wear(_ variant: String, for slot: Slot) {
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
