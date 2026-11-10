import AvatarArt
import AvatarDomain
import CharacterEditorDomain
import Contracts

extension Catalog {
    /// What the placeholder character's bundled art offers a member whose 商店街 is `stock` (the
    /// server's, or the starter street while it isn't known yet): the species in its
    /// `editor.json`, the stores the stock lists that the art has, in the stock's order, the
    /// pieces the member owns or may take, the locked ones hanging as 「？」 boxes, every prop
    /// (props never need unlocking, Tracy 2026-11-09), every bundled hair and face part,
    /// and their preset colors. A closed store (its switch off) stays on the street only as the
    /// member's own rack, when they own something there.
    public static func placeholder(
        stock: StreetStock? = nil, gifts: [String] = []
    ) throws(AvatarError) -> Catalog {
        let stock = stock ?? StarterStock.shared.current
        let choices = try PlaceholderCharacter.editorChoices()
        var props = choices.props.map(\.id)
        let owned = Set(stock.pieces.filter { $0.state == .owned }.map(\.id))
        let boxed: [(String, Int)] = stock.pieces.compactMap { piece in
            guard case .locked(let left) = piece.state, !owned.contains(piece.id) else { return nil }
            return (piece.id, left)
        }
        let toGo = Dictionary(boxed, uniquingKeysWith: min)
        let out = Set(stock.pieces.filter { $0.state == .available || $0.state == .owned }.map(\.id))
        let stores = street(stock, art: Set(choices.stores.map(\.id)), owned: owned)
        var variants = choices.wear.mapValues { pieces in pieces.filter { out.contains($0.id) }.map(\.id) }
        let stillLocked = choices.wear.mapValues { pieces -> [String: Int] in
            let onRack: [(String, Int)] = pieces.compactMap { piece in toGo[piece.id].map { (piece.id, $0) } }
            return Dictionary(onRack, uniquingKeysWith: min)
        }.filter { !$0.value.isEmpty }
        let given = hang(gifts, variants: &variants, props: &props)
        for slot in ["hair"] + PlaceholderCharacter.faceSlots {
            variants[slot] = PlaceholderCharacter.variants(for: slot)
        }
        var swatches: [Slot: [String: [RGBAColor]]] = [:]
        var originals: [Slot: [String: RGBAColor]] = [:]
        // Typed piece by piece: as one literal, Xcode's type checker gives up on it.
        let bodies: [String] = choices.species.flatMap(\.bodies)
        var recolorable: [(Slot, [String])] = [("body", bodies)]
        for slot: Slot in ["hair", "eyes", "brows"] + Catalog.clothingSlots {
            recolorable.append((slot, variants[slot] ?? []))
        }
        for (slot, names) in recolorable {
            for name in names {
                let colors = PlaceholderCharacter.swatches(for: slot, wearing: name)
                guard !colors.isEmpty, let tones = PlaceholderCharacter.tones(for: slot, wearing: name) else {
                    continue
                }
                swatches[slot, default: [:]][name] = colors
                originals[slot, default: [:]][name] = tones.base
            }
        }
        var storeOf: [String: String] = [:]
        for piece in choices.wear.values.joined() {
            storeOf[piece.id] = piece.store
        }
        return Catalog(
            species: choices.species, variants: variants, props: props, swatches: swatches,
            originals: originals,
            defaults: try PlaceholderCharacter.rig().defaults.filter { Catalog.dressSlots.contains($0.key) },
            stores: stores, storeOf: storeOf, locked: stillLocked, gifts: given)
    }

    /// Hangs what was given the member (the coach's gifts they opened, the team's pieces) in the
    /// slot whose art holds each, and gives back the ones hung; one this build has no art for yet
    /// is left out.
    private static func hang(_ gifts: [String], variants: inout [Slot: [String]], props: inout [String]) -> [String] {
        var given: [String] = []
        for gift in gifts {
            guard let slot = PlaceholderCharacter.slot(holding: gift) else { continue }
            given.append(gift)
            if slot == "prop" {
                if !props.contains(gift) { props.append(gift) }
            } else if !(variants[slot] ?? []).contains(gift) {
                variants[slot, default: []].append(gift)
            }
        }
        return given
    }

    /// The pieces that came to the member and wait on 商店街 until claimed (领取): the ones they
    /// unlocked, and the ones the street holds as theirs without an unlock (a limited store's
    /// starters while it is open, or anything already claimed).
    public static func arrived(unlocks: [Unlock], stock: StreetStock?) -> Set<String> {
        let unlocked = unlocks.filter { $0.kind == .piece }.map(\.id)
        let owned = (stock?.pieces ?? []).filter { $0.state == .owned }.map(\.id)
        return Set(unlocked).union(owned)
    }

    /// The stores the stock lists that the art has, the ones the member can walk into first, each
    /// group in the stock's order (Tracy, 2026-11-06): an open one, walked into once earned (the
    /// server lists a store's starters and boxes only then), and a closed one only as the rack of
    /// what the member owns there.
    private static func street(_ stock: StreetStock, art: Set<String>, owned: Set<String>) -> [EditorChoices.Store] {
        let stores = stock.stores.filter { art.contains($0.id) }.compactMap { store -> EditorChoices.Store? in
            let pieces = stock.pieces.filter { $0.store == store.id }
            let ownsSome = pieces.contains { owned.contains($0.id) }
            guard store.isOpen || ownsSome else { return nil }
            return EditorChoices.Store(
                id: store.id, isOpen: ownsSome || pieces.contains { !owned.contains($0.id) }, toGo: store.toGo)
        }
        return stores.filter(\.isOpen) + stores.filter { !$0.isOpen }
    }
}
