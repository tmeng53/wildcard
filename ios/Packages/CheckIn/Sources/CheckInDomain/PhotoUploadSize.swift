/// How big a photo goes up, as Instagram does it: at most 1080 px on its short edge, so a portrait
/// photo fills a feed card (some 1080 px wide on a 3× phone) as sharply as a landscape one, and at
/// most 1920 on its long edge (a 9:16 photo); never larger than it was.
public enum PhotoUploadSize {
    public static let maxShortEdge = 1080
    public static let maxLongEdge = 1920

    /// The long edge, in pixels, a `width` × `height` photo is shrunk to.
    public static func longEdge(width: Int, height: Int) -> Int {
        let long = max(width, height)
        let short = min(width, height)
        // A photo whose size can't be read goes up as before sizes were read: 1080 on the long edge.
        guard short > 0 else { return maxShortEdge }
        let atShortEdge = (Double(long) * Double(maxShortEdge) / Double(short)).rounded(.down)
        return min(long, maxLongEdge, Int(atShortEdge))
    }
}
