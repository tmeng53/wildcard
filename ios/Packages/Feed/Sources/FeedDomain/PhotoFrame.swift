import Contracts

/// The shape of a post's photo box, as Instagram does it: the cover's own shape, kept between
/// 4:5 portrait and 1.91:1 landscape, the rest of the post's photos filling the same box. A
/// cover saved without its size gets the old landscape box.
public enum PhotoFrame {
    /// The tallest box, width over height.
    public static let tallest = 4.0 / 5.0
    /// The widest box, width over height.
    public static let widest = 1.91
    /// The box for a cover saved without its size.
    public static let unknown = 3.0 / 2.0

    /// Width over height of the box `photos` show in.
    public static func aspectRatio(of photos: Photos) -> Double {
        guard let size = photos.cover.size else { return unknown }
        return min(max(size.aspectRatio, tallest), widest)
    }
}
