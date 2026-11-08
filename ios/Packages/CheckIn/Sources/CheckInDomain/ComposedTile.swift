import Contracts
import Foundation

/// One tile in the compose page's photo row: a photo, or the workout's map or chart. The row's
/// order is the post's: the first tile is the 封面.
public enum ComposedTile: Hashable, Sendable, Identifiable {
    case photo(ComposedPhoto)
    case workout(WorkoutTile)

    public var id: String {
        switch self {
        case .photo(let photo): photo.id
        case .workout(.map): "workout.map"
        case .workout(.chart): "workout.chart"
        }
    }

    /// The workout's map or chart, not a photo.
    public var isWorkout: Bool {
        if case .workout = self { true } else { false }
    }

    /// A saved 训练's tiles in its order; a meal's, a 请假条's or a manual 训练's photos.
    public static func of(_ checkIn: CheckIn) -> [ComposedTile] {
        guard case .trained(let training) = checkIn.entry else { return ComposedPhoto.of(checkIn).map(Self.photo) }
        return training.tiles.map { tile in
            switch tile {
            case .photo(let ref): .photo(.saved(ref))
            case .workout(let workout): .workout(workout)
            }
        }
    }

    /// A post written on the phone, as the compose page shows it again: its photos with the
    /// workout's map and chart each at its place among them.
    public static func of(_ body: PostBody) -> [ComposedTile] {
        var tiles = body.photos.map { ComposedTile.photo(.new($0)) }
        guard let workout = body.workout else { return tiles }
        let placed = workout.tiles.compactMap { tile in workout.position(of: tile).map { (tile, $0) } }
        for (tile, position) in placed.sorted(by: { $0.1 < $1.1 }) {
            tiles.insert(.workout(tile), at: min(max(position - 1, 0), tiles.count))
        }
        return tiles
    }
}

extension [ComposedTile] {
    /// The photos in the row's order, without the workout's tile.
    public var photos: [ComposedPhoto] {
        compactMap { if case .photo(let photo) = $0 { photo } else { nil } }
    }

    /// Where the workout's map and chart are, 1 being the cover; one taken off isn't there.
    public var workoutTilePositions: [WorkoutTile: Int] {
        var positions: [WorkoutTile: Int] = [:]
        for (index, tile) in enumerated() { if case .workout(let workout) = tile { positions[workout] = index + 1 } }
        return positions
    }

    /// Moves the tile with `id` to where `target` is, as a drag and drop does: dropped on a tile
    /// further along, it goes after it; on one before, before it.
    public mutating func move(_ id: String, onto target: String) {
        guard id != target, let origin = firstIndex(where: { $0.id == id }),
            let destination = firstIndex(where: { $0.id == target })
        else { return }
        insert(remove(at: origin), at: destination)
    }
}
