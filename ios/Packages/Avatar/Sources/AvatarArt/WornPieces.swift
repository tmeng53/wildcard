import AvatarDomain

/// A piece of clothing or a prop a look wears, as a squadmate's card lists it: what it is, the
/// slot it is worn in and the store whose rack it hangs on (nil for one on no rack, such as a
/// coach's gift or a prop).
public struct WornPiece: Hashable, Sendable, Identifiable {
    public let slot: Slot
    /// The variant (`powder-salmon`).
    public let piece: String
    public let store: String?

    public init(slot: Slot, piece: String, store: String?) {
        (self.slot, self.piece, self.store) = (slot, piece, store)
    }

    /// One a slot, so a piece worn in two slots is two rows.
    public var id: String { "\(slot)/\(piece)" }
}

extension EditorChoices {
    /// The slots a squadmate's card lists, head to foot and the prop last.
    public static let listedSlots: [Slot] = ["hat", "top", "acc", "bottom", "shoes", "prop"]

    /// What `variants` (a look as it is drawn, the rig's defaults filled in) wears in each listed
    /// slot, head to foot, with each piece's store from the racks.
    public func worn(_ variants: [Slot: String]) -> [WornPiece] {
        Self.listedSlots.compactMap { slot in
            guard let id = variants[slot] else { return nil }
            return WornPiece(slot: slot, piece: id, store: wear[slot]?.first { $0.id == id }?.store)
        }
    }
}

extension PlaceholderCharacter {
    /// What `outfit` wears as this build draws it (`drawable(_:)`, the rig's defaults where it
    /// picks nothing), head to foot; empty when the art can't be read.
    public static func worn(_ outfit: Outfit) -> [WornPiece] {
        guard let drawn = try? drawable(outfit), let rig = try? rig(), let choices = try? editorChoices() else {
            return []
        }
        return choices.worn(rig.defaults.merging(drawn.variants) { _, picked in picked })
    }
}
