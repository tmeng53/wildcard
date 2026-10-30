#if canImport(SwiftUI)
import AvatarDomain
import AvatarUI
import SwiftUI

/// Tile pictures: the person's own character in each choice, standing at rest, or a piece of
/// clothing on its own. Each is built once, off the main actor, and kept while the editor is
/// open.
@MainActor
final class ThumbnailCache {
    struct Entry {
        let drawing: FigureDrawing
        let placements: [Placement]
        /// What a piece on its own covers, which its tile fits; nil for the whole character.
        let bounds: CGRect?
    }

    /// An outfit, and the one slot to draw when a piece shows on its own.
    struct Key: Hashable {
        let outfit: Outfit
        let only: Slot?
    }

    private var entries: [Key: Entry] = [:]
    /// Enough for every tile of a few looks; past it the cache starts over.
    private let limit = 400

    func entry(for key: Key) -> Entry? {
        entries[key]
    }

    func load(_ key: Key) async -> Entry? {
        if let entry = entries[key] { return entry }
        guard var figure = try? await CharacterEditorModel.figure(wearing: key.outfit) else { return nil }
        if let slot = key.only { figure = figure.wearing(only: slot) }
        let drawing = FigureDrawing(figure)
        let placements = figure.layout(figure.restPose)
        let entry = Entry(
            drawing: drawing, placements: placements, bounds: key.only == nil ? nil : drawing.bounds(placements))
        if entries.count >= limit { entries.removeAll() }
        entries[key] = entry
        return entry
    }
}

/// The character in `outfit`, cropped to the part that changes, such as the head for a hat;
/// or, given `only`, that slot's piece on its own, filling the tile.
struct Thumbnail: View {
    let outfit: Outfit
    var only: Slot?
    let crop: CGRect
    let cache: ThumbnailCache
    /// The last picture shown, kept while the next one builds so the tile never blanks.
    @State private var shown: ThumbnailCache.Entry?
    /// The room left around a piece on its own, in canvas points.
    private let margin: Double = 6

    var body: some View {
        let key = ThumbnailCache.Key(outfit: outfit, only: only)
        ZStack {
            if let entry = cache.entry(for: key) ?? shown {
                CharacterCanvas(
                    drawing: entry.drawing, placements: entry.placements,
                    crop: entry.bounds?.insetBy(dx: -margin, dy: -margin) ?? crop)
            }
        }
        .task(id: key) {
            shown = await cache.load(key)
        }
        .accessibilityHidden(true)
    }
}

/// The part of the 240×320 canvas each tab's thumbnails show.
enum ThumbnailCrop {
    /// Head and shoulders, for bodies, hair and hats.
    static let head = CGRect(x: 20, y: 40, width: 200, height: 200)
    static let top = CGRect(x: 30, y: 160, width: 180, height: 180)
    static let bottom = CGRect(x: 45, y: 195, width: 150, height: 150)
    /// The hand and what it holds, down to the foot of the longest prop (the yoga mat).
    static let prop = CGRect(x: 40, y: 125, width: 190, height: 190)
    /// Close on the face, a little higher for brows and lower for the mouth.
    static let face = CGRect(x: 62, y: 112, width: 116, height: 116)
    static let brows = CGRect(x: 62, y: 100, width: 116, height: 116)
    static let mouth = CGRect(x: 62, y: 130, width: 116, height: 116)

    static func of(_ slot: Slot) -> CGRect {
        switch slot.rawValue {
        case "top": top
        case "bottom": bottom
        case "prop": prop
        case "eyes", "cheeks", "glasses": face
        case "brows": brows
        case "mouth": mouth
        default: head
        }
    }
}
#endif
