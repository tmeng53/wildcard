import Foundation

/// The 软糖星 (jelly star, Tracy 2026-11-12): a chubby five-pointed star, rounded by a thick
/// round-joined outline of its own colour, standing on a darker copy of itself for thickness, with
/// a shine at its top left when lit. Flat tones only, as the 软糖厚章 badges are drawn. Measures are
/// on a 32-point square; `JellyStar` in DesignSystemUI scales them to its size.
public enum JellyStarShape {
    public static let side = 32.0
    public static let center = (x: 16.0, y: 16.0)
    public static let outerRadius = 12.2
    /// The inner corners' distance, as a share of the points': higher is chubbier.
    public static let innerRatio = 0.52
    /// The outline that rounds every corner, in the star's own colour.
    public static let roundingWidth = 4.2
    /// How far below the face its thickness shows.
    public static let depth = 2.2
    /// The shine: an oval leaning back at the top left, and a small dot beside it.
    public static let shine = (x: 11.6, y: 11.6, radiusX: 3.1, radiusY: 1.7, degrees: -35.0)
    public static let sparkle = (x: 15.6, y: 9.6, radius: 0.9)

    /// The star's ten corners, points and inner corners in turn, from the top point clockwise.
    public static var corners: [(x: Double, y: Double)] {
        (0..<10).map { index in
            let radius = index.isMultiple(of: 2) ? outerRadius : outerRadius * innerRatio
            let angle = Double.pi / 2 - Double(index) * Double.pi / 5
            return (center.x + radius * cos(angle), center.y - radius * sin(angle))
        }
    }
}
