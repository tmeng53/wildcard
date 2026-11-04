import AvatarArt
import AvatarDomain
import CharacterEditorDomain
import Contracts

extension Catalog {
    /// What the placeholder character's bundled art offers a member who unlocked `unlocks`: the
    /// species and stores in its `editor.json`, the clothes of the stores open to them but the
    /// `locked` pieces, which hang there as 「？」 boxes, the props they hold (the starters, with
    /// nothing unlocked), every bundled hair and face part, and their preset colors. A store on a
    /// switch (POWDER DAY) unlocks only while `isOn` says the switch is on: while it is off the
    /// store stays on the street as the member's own rack, what they hold worn all year, without
    /// the boxes.
    public static func placeholder(
        unlocks: [Unlock] = [], locked: [LockedPiece] = [],
        isOn: (String) -> Bool = { StoreSwitches.shared.isOn($0) }
    ) throws(AvatarError) -> Catalog {
        let choices = try PlaceholderCharacter.editorChoices()
        let unlocked = { (kind: Unlock.Kind) in Set(unlocks.filter { $0.kind == kind }.map(\.id)) }
        let (unlockedStores, unlockedProps) = (unlocked(.store), unlocked(.prop))
        let everyStore = choices.stores.map { store in
            EditorChoices.Store(
                id: store.id, isOpen: store.isOpen || unlockedStores.contains(store.id), switchId: store.switchId)
        }
        let open = Set(everyStore.filter(\.isOpen).map(\.id))
        let packedAway = Set(everyStore.filter { $0.switchId.map { !isOn($0) } ?? false }.map(\.id))
        let props = choices.props.filter { $0.isOpen || unlockedProps.contains($0.id) }.map(\.id)
        // A piece the member holds is never locked, whatever an older list says.
        let unlockedPieces = unlocked(.piece)
        let toGo = Dictionary(
            locked.filter { !unlockedPieces.contains($0.id) }.map { ($0.id, $0.checkInsToGo) },
            uniquingKeysWith: min)
        var variants = choices.wear.mapValues { pieces in
            pieces.filter { open.contains($0.store) && toGo[$0.id] == nil }.map(\.id)
        }
        let stillLocked = boxes(of: choices.wear, toGo: toGo, packedAway: packedAway)
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
            stores: everyStore, storeOf: storeOf, locked: stillLocked)
    }

    /// The 「？」 boxes by slot: each piece still to go, but none in a store packed away while its
    /// switch is off, since nothing unlocks there until it is on again.
    private static func boxes(
        of wear: [Slot: [EditorChoices.Wearable]], toGo: [String: Int], packedAway: Set<String>
    ) -> [Slot: [String: Int]] {
        wear.mapValues { pieces in
            Dictionary(
                uniqueKeysWithValues: pieces.filter { !packedAway.contains($0.store) }.compactMap { piece in
                    toGo[piece.id].map { (piece.id, $0) }
                })
        }.filter { !$0.value.isEmpty }
    }
}
