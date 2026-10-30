import Foundation

// A prop held in a hand: the mitten fist drawn in the rig's own skin takes the colors of the
// wearer's hand, and a prop whose `hold.json` asks it to keep level hangs level however the
// arm carrying it turns.

extension Figure {
    /// The worn variant whose `hold.json` asks it to keep level, if any.
    static func level(
        _ variants: [Slot: String], _ rig: Rig, _ parents: [Int?], _ source: some ArtSource
    ) throws(AvatarError) -> Level? {
        for (slot, variant) in variants.sorted(by: { $0.key.description < $1.key.description }) {
            let path = "\(slot)/\(variant)/hold.json"
            guard let text = source.text(at: path) else { continue }
            let file: HoldFile
            do {
                file = try decodeJSON(Data(text.utf8), version: 1, shape: HoldFile.shape)
            } catch .malformedJSON(let problem) {
                throw .malformedJSON("\(path)\(problem)")
            }
            guard let arm = rig.parts.firstIndex(where: { $0.id == file.level }) else {
                throw .unknownArm(art: path, arm: file.level)
            }
            let held = rig.parts.indices.filter { index in
                parents[index] == arm && rig.parts[index].layers.contains { $0.slot == slot }
            }
            return Level(variant: variant, parts: held)
        }
        return nil
    }

    /// The hand in a part's body art: its last shape, drawn over the arm.
    static func hand(_ art: Artwork?) -> Rig.Skin? {
        guard let shape = art?.shapes.last, let fill = shape.fill, let stroke = shape.stroke else { return nil }
        return Rig.Skin(fill: fill, stroke: stroke.color)
    }

    /// The art with the rig's skin fill and outline swapped for the hand's.
    static func painted(_ art: Artwork, from skin: Rig.Skin, to hand: Rig.Skin) -> Artwork {
        func moved(_ color: RGBAColor) -> RGBAColor {
            let target = color.sameRGB(as: skin.fill) ? hand.fill : color.sameRGB(as: skin.stroke) ? hand.stroke : color
            return RGBAColor(red: target.red, green: target.green, blue: target.blue, opacity: color.opacity)
        }
        var painted = art
        painted.shapes = art.shapes.map { shape in
            var shape = shape
            shape.fill = shape.fill.map(moved)
            if let stroke = shape.stroke { shape.stroke?.color = moved(stroke.color) }
            return shape
        }
        return painted
    }

    /// Paints every layer held in a hand the colors of that hand.
    static func paintHands(
        _ built: inout [Part], held: [(part: Int, layer: Int, hand: PartID)],
        bodies: [PartID: Artwork], skin: Rig.Skin?
    ) throws(AvatarError) {
        for (part, layer, hand) in held {
            guard let skin, let paint = Self.hand(bodies[hand]) else { throw .noHand(hand) }
            built[part].art[layer] = Self.painted(built[part].art[layer], from: skin, to: paint)
        }
    }
}

/// `{"version": 1, "level": "armR"}`: the arm a variant keeps level in.
private struct HoldFile: Decodable {
    static let shape = JSONShape.object(["version": .value, "level": .value])

    let level: PartID
}
