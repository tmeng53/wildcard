#if canImport(SwiftUI)
import AvatarDomain
import AvatarUI
import SwiftUI

/// Tile pictures: the person's own character in each choice, standing at rest. Each is built
/// once, off the main actor, and kept while the editor is open.
@MainActor
final class ThumbnailCache {
    struct Entry {
        let drawing: FigureDrawing
        let placements: [Placement]
    }

    private var entries: [Outfit: Entry] = [:]
    /// Enough for every tile of a few looks; past it the cache starts over.
    private let limit = 400

    func entry(for outfit: Outfit) -> Entry? {
        entries[outfit]
    }

    func load(_ outfit: Outfit) async -> Entry? {
        if let entry = entries[outfit] { return entry }
        guard let figure = try? await CharacterEditorModel.figure(wearing: outfit) else { return nil }
        let entry = Entry(drawing: FigureDrawing(figure), placements: figure.layout(figure.restPose))
        if entries.count >= limit { entries.removeAll() }
        entries[outfit] = entry
        return entry
    }
}

/// The character in `outfit`, cropped to the part that changes, such as the head for a hat.
struct Thumbnail: View {
    let outfit: Outfit
    let crop: CGRect
    let cache: ThumbnailCache
    /// The last picture shown, kept while the next one builds so the tile never blanks.
    @State private var shown: ThumbnailCache.Entry?

    var body: some View {
        ZStack {
            if let entry = cache.entry(for: outfit) ?? shown {
                CharacterCanvas(drawing: entry.drawing, placements: entry.placements, crop: crop)
            }
        }
        .task(id: outfit) {
            shown = await cache.load(outfit)
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
    /// The hand and what it holds.
    static let prop = CGRect(x: 50, y: 110, width: 190, height: 190)
    /// The face, close: eyes, cheeks and glasses.
    static let face = CGRect(x: 62, y: 112, width: 116, height: 116)
    /// The face a little higher, for brows, and lower, for the mouth.
    static let brows = CGRect(x: 62, y: 100, width: 116, height: 116)
    static let mouth = CGRect(x: 62, y: 130, width: 116, height: 116)
    /// The feet.
    static let shoes = CGRect(x: 76, y: 258, width: 88, height: 88)

    static func of(_ slot: Slot) -> CGRect {
        switch slot.rawValue {
        case "top": top
        case "bottom": bottom
        case "prop": prop
        case "eyes", "cheeks", "glasses": face
        case "brows": brows
        case "mouth": mouth
        case "shoes": shoes
        default: head
        }
    }
}
#endif
