#if os(iOS)
import AvatarArt
import AvatarDomain
import CharacterEditorDomain
import Contracts
import Foundation
import Observation

/// 商店街, its own page from 我 (the approved wardrobe design, 2026-11-04): where the member gets
/// clothes. Each store is a storefront along the street, then the open store's rack. A piece the
/// member unlocked waits there with NEW until they claim it (领取) into their wardrobe; one this
/// phone hasn't opened waits in its 「？」 box first. Nothing is bought: clothes come only by training.
@MainActor @Observable
public final class StreetModel {
    /// One piece on a rack, as the member finds it.
    enum Shelf: Equatable {
        /// Still locked: a 「？」 box and how many 练了 open it.
        case locked(toGo: Int)
        /// Unlocked, its box not opened on this phone: in the pop-up's boxes; on its rack it shows
        /// as itself with NEW, and a tap opens it and offers 领取.
        case boxed
        /// Unlocked and opened, not claimed: NEW, and a tap offers 领取.
        case new
        /// In the wardrobe (claimed, or it came with its store): 已拥有, and a tap tries it on.
        case owned
    }

    /// The boxes waiting, in the pop-up over the street.
    struct Arrival: Equatable {
        let pieces: [String]
        /// The one store they all came to, or nil when they came to several.
        let store: String?
    }

    /// The member's look, so each piece shows in the colors it would be worn in.
    let draft: CharacterDraft
    var catalog: Catalog { draft.catalog }
    /// The store open; nil shows the street.
    public private(set) var store: String?
    /// The piece whose 领取 sheet is up.
    var sheet: String?
    /// The store whose 「练这些运动解锁」 tip is up.
    var tip: String?
    /// The boxes in the pop-up, until opened or left.
    private(set) var arrival: Arrival?
    /// The piece just claimed, for the 「已放进衣橱」 notice.
    var claimedNotice: ClaimedPiece?
    /// A claim that couldn't be saved.
    private(set) var claimFailed = false
    let thumbnails = ThumbnailCache()

    struct ClaimedPiece: Identifiable, Equatable {
        let id: String
    }

    @ObservationIgnored private let marks: any WardrobeMarks
    @ObservationIgnored private let claimPiece: (String) async -> Bool
    @ObservationIgnored private let tryOnPiece: (String) -> Void
    /// The pieces the member unlocked that hang on a rack this build has.
    private let arrived: Set<String>
    /// What counts towards each piece with a rule, locked or unlocked: its sports, empty for any.
    private let sportsOf: [String: [Sport]]
    private var claimed: Set<String>
    private var opened: Set<String>
    /// The pieces waiting when the street last opened, so 我's dot clears at once.
    private var noticed: Set<String>

    /// The street for a member with `standing` (what they unlocked and claimed, and their 商店街 as
    /// the server works it out), dressed in `look`. `claim` saves a 领取 and answers whether it was kept; `tryOn`
    /// opens the editor wearing a piece.
    public static func placeholder(
        look: Outfit, standing: UnlockStanding, marks: any WardrobeMarks = MemoryWardrobeMarks(),
        claim: @escaping (String) async -> Bool, tryOn: @escaping (String) -> Void
    ) throws(AvatarError) -> StreetModel {
        let catalog = try Catalog.placeholder(unlocks: standing.unlocks, stock: standing.stock)
        return StreetModel(
            draft: CharacterDraft(catalog: catalog, look: look, persona: .energetic, nickname: ""),
            unlocks: standing.unlocks, stock: standing.stock, claimed: standing.claimed, marks: marks,
            claim: claim, tryOn: tryOn)
    }

    init(
        draft: CharacterDraft, unlocks: [Unlock], stock: StreetStock, claimed: Set<String>,
        marks: any WardrobeMarks, claim: @escaping (String) async -> Bool, tryOn: @escaping (String) -> Void
    ) {
        self.draft = draft
        self.marks = marks
        (claimPiece, tryOnPiece) = (claim, tryOn)
        let pieces = unlocks.filter { $0.kind == .piece }
        arrived = Catalog.arrived(unlocks: unlocks, stock: stock).filter { draft.catalog.storeOf[$0] != nil }
        var sports: [String: [Sport]] = [:]
        for piece in pieces { sports[piece.id] = piece.sports }
        for piece in stock.pieces {
            if case .locked = piece.state { sports[piece.id] = piece.sports }
        }
        sportsOf = sports
        // A piece the member already wears was found before boxes came in: it is theirs.
        let worn = Set(draft.picks.variants.values)
        self.claimed = claimed.union(worn)
        opened = marks.opened.union(claimed).union(worn)
        noticed = marks.noticed
    }

    // MARK: What each piece is

    func shelf(_ piece: String) -> Shelf {
        if let toGo = catalog.locked.values.lazy.compactMap({ $0[piece] }).first { return .locked(toGo: toGo) }
        guard arrived.contains(piece), !claimed.contains(piece) else { return .owned }
        return opened.contains(piece) ? .new : .boxed
    }

    /// The pieces that came in and wait unclaimed, in street order.
    var waiting: [String] {
        catalog.stores.filter(\.isOpen).flatMap { catalog.rack(of: $0.id).map(\.variant) }
            .filter { [.new, .boxed].contains(shelf($0)) }
    }

    /// Whether the store has a piece waiting for the member, for NEW by its name on the street.
    func hasNews(_ store: String) -> Bool {
        catalog.rack(of: store).contains { [.new, .boxed].contains(shelf($0.variant)) }
    }

    /// The sports that open the store's pieces with a rule, the same list its 「练这些运动解锁」 tip
    /// and its card show; nil when none has a rule, and empty when any sport counts.
    func sports(of store: String) -> [Sport]? {
        let rules = (catalog.rack(of: store).map(\.variant) + catalog.lockedRack(of: store).map(\.variant))
            .compactMap { sportsOf[$0] }
        guard !rules.isEmpty else { return nil }
        if rules.contains(where: \.isEmpty) { return [] }
        var seen: Set<Sport> = []
        return rules.joined().filter { seen.insert($0).inserted }
    }

    /// A piece's slot and the member wearing it, for its picture.
    func preview(of piece: String) -> (slot: Slot, outfit: Outfit)? {
        guard let store = catalog.storeOf[piece],
            let slot =
                (catalog.rack(of: store).first { $0.variant == piece }?.slot
                    ?? catalog.lockedRack(of: store).first { $0.variant == piece }?.slot)
        else { return nil }
        var wearing = draft
        wearing.pick(piece, for: slot)
        return (slot, wearing.outfit)
    }

    /// Whether 我's shopfront wears its dot: a piece came in since the street last opened.
    public var hasUnseenNews: Bool {
        !Set(waiting).isSubset(of: noticed)
    }

    /// The street opened: the shopfront's dot clears until another piece comes in.
    public func didOpen() {
        marks.notice(Set(waiting))
        noticed = marks.noticed
    }

    // MARK: Walking the street

    /// Walks into an open store; a closed one stays shut, its shutter saying how it unlocks.
    func visit(_ store: EditorChoices.Store) {
        guard store.isOpen else { return }
        (self.store, tip) = (store.id, nil)
    }

    /// Back out to the street.
    func leaveStore() {
        (store, tip, sheet) = (nil, nil, nil)
    }

    /// Opens on what training unlocked, from its notice: a store opens on its rack; new pieces open
    /// their store with the pop-up of every box this phone hasn't opened over it.
    public func show(_ kind: Unlock.Kind, item: String) {
        switch kind {
        case .store:
            if let store = catalog.stores.first(where: { $0.id == item && $0.isOpen }) { visit(store) }
        case .piece:
            if let id = catalog.storeOf[item], let store = catalog.stores.first(where: { $0.id == id && $0.isOpen }) {
                visit(store)
            }
            showArrivals()
        case .prop:
            break
        }
    }

    /// Puts the pop-up up with every box this phone hasn't opened, if any.
    func showArrivals() {
        let pieces = waiting.filter { shelf($0) == .boxed }
        guard !pieces.isEmpty else { return }
        let stores = Set(pieces.compactMap { catalog.storeOf[$0] })
        arrival = Arrival(pieces: pieces, store: stores.count == 1 ? stores.first : nil)
    }

    /// 一键全开, once the boxes' opening has played: every box opens and each piece wears NEW on its
    /// rack, the store they came to open (the street, when they came to several).
    func openArrival() {
        guard let arrival else { return }
        self.arrival = nil
        marks.open(Set(arrival.pieces))
        opened.formUnion(arrival.pieces)
        if arrival.store == nil { store = nil }
    }

    /// 先不了: the pieces wait on their racks with NEW, each offering 领取 when tapped.
    func leaveArrival() {
        arrival = nil
    }

    /// A tap on a piece: one that came in offers 领取 (its box, if this phone hadn't opened it,
    /// opens on the way), one in the wardrobe is tried on in the editor.
    func tap(_ piece: String) {
        switch shelf(piece) {
        case .new: sheet = piece
        case .owned: tryOnPiece(piece)
        case .boxed:
            marks.open([piece])
            opened.insert(piece)
            sheet = piece
        case .locked: tip = catalog.storeOf[piece]
        }
    }

    /// 领取: the piece goes in the wardrobe at once and 「已放进衣橱」 drops in; it comes back out,
    /// NEW again, if saving fails.
    func claim(_ piece: String) async {
        sheet = nil
        claimFailed = false
        claimed.insert(piece)
        guard await claimPiece(piece) else {
            claimed.remove(piece)
            claimFailed = true
            return
        }
        claimedNotice = ClaimedPiece(id: piece)
    }

    /// 「穿上看看」 on the notice: the editor, wearing the piece just claimed.
    func tryOn(_ piece: String) {
        claimedNotice = nil
        tryOnPiece(piece)
    }
}
#endif
