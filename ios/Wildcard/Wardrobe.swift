import CharacterEditorUI
import Contracts
import MeDomain
import Observation

/// Where 我 dresses the member: 商店街, kept for the shopfront's dot and opened in 我's place, and
/// the character editor over everything. An unlock opens here, from the home's banner and 通知
/// alike.
@MainActor @Observable
final class Wardrobe {
    /// 商店街 for the member as 我 last read them; made again when that changes (while it is open,
    /// only when the street itself did).
    private(set) var shop: StreetModel?
    /// The street `shop` was made from, so an open one is made again only when the street changed,
    /// not when a claim on it saved.
    @ObservationIgnored private var madeFrom: Street?
    var showsShop = false
    var editor: CharacterEditorModel?
    @ObservationIgnored private let profile: MeModel
    /// The member whose marks this phone keeps; nil on the sample squad.
    @ObservationIgnored private let member: () -> String?
    /// The sample squad's marks, whose member is new each launch: kept while the tabs are up.
    @ObservationIgnored private let sampleMarks = MemoryWardrobeMarks()

    init(profile: MeModel, member: @escaping () -> String?) {
        (self.profile, self.member) = (profile, member)
    }

    /// What this phone remembers of the member's boxes and NEW pieces.
    private var marks: any WardrobeMarks {
        member().map { DeviceWardrobeMarks(member: $0) } ?? sampleMarks
    }

    /// Whether 我's shopfront wears its dot.
    var hasNews: Bool { shop?.hasUnseenNews ?? false }

    /// Opens the editor on the member's own character.
    func editCharacter() {
        guard let overview = profile.overview else { return }
        let character = overview.character
        editor = try? CharacterEditorModel.placeholder(
            look: character.outfit, persona: character.persona, nickname: character.nickname,
            unlocks: overview.unlocks, stock: overview.stock, claimed: overview.claimed, marks: marks)
    }

    /// 我's shopfront: the street as it was last made at once, then read again, so a store that
    /// opened since shows without waiting for the next launch.
    func openShop() {
        if shop == nil { shop = makeShop() }
        showsShop = shop != nil
        Task { await profile.reload() }
    }

    /// What 商店街 is made from, and whether it is open, for `refresh`.
    var key: Key? {
        profile.overview.map {
            Key(
                character: $0.character,
                standing: UnlockStanding(
                    unlocks: $0.unlocks, claimed: $0.claimed, stock: $0.stock ?? StarterStock.shared.current),
                open: showsShop)
        }
    }

    struct Key: Hashable {
        let character: MeCharacter
        let standing: UnlockStanding
        let open: Bool
    }

    /// Makes 商店街 again from what 我 read. An open one is made again only when the street changed
    /// (a store opened or closed, a piece came in), keeping the store it is in.
    func refresh() {
        guard showsShop else {
            shop = makeShop()
            return
        }
        guard let overview = profile.overview, Street(overview) != madeFrom else { return }
        let inside = shop?.store
        shop = makeShop()
        if let inside { shop?.show(.store, item: inside) }
    }

    /// What a street is made from, apart from what the member claimed on it.
    private struct Street: Equatable {
        let unlocks: [Unlock]
        let stock: StreetStock?

        init(_ overview: MeOverview) {
            (unlocks, stock) = (overview.unlocks, overview.stock)
        }
    }

    /// Where an unlock opens, read again first so what just opened is open there: a store on its
    /// rack on 商店街, pieces there with their boxes' pop-up over it, a prop on the editor's 道具.
    func open(_ kind: Unlock.Kind, item: String) async {
        await profile.reload()
        if kind == .prop {
            editCharacter()
            editor?.show(kind, item: item)
        } else {
            shop = makeShop()
            showsShop = shop != nil
            shop?.show(kind, item: item)
        }
    }

    /// A claim saves through 我, and a piece tried on opens the editor over the street, so back
    /// returns to it.
    private func makeShop() -> StreetModel? {
        guard let overview = profile.overview else { return nil }
        madeFrom = Street(overview)
        let profile = profile
        return try? StreetModel.placeholder(
            look: overview.character.outfit,
            standing: UnlockStanding(
                unlocks: overview.unlocks, claimed: overview.claimed,
                stock: overview.stock ?? StarterStock.shared.current),
            marks: marks,
            noticeHold: LaunchOptions.bubbleHold,
            claim: { await profile.claim($0) },
            tryOn: { [weak self] piece in
                self?.editCharacter()
                self?.editor?.tryOn(piece)
            })
    }
}
