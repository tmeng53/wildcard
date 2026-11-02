import Contracts
import FeedDomain
import Testing

private func photos(_ sizes: (width: Int, height: Int)?...) throws -> Photos {
    var refs: [PhotoRef] = []
    for (index, size) in sizes.enumerated() {
        let pixels = try size.map { size throws(ContractsError) in try PhotoSize(width: size.width, height: size.height)
        }
        refs.append(try PhotoRef(path: "m/\(index)", size: pixels))
    }
    return try Photos(refs)
}

@Test func theBoxTakesTheCoversShape() throws {
    #expect(PhotoFrame.aspectRatio(of: try photos((1080, 1350))) == 0.8)
    #expect(PhotoFrame.aspectRatio(of: try photos((1080, 1080))) == 1)
    #expect(PhotoFrame.aspectRatio(of: try photos((1080, 720), (1080, 1350))) == 1.5)
}

@Test func aTallerOrWiderCoverIsCroppedToTheLimits() throws {
    // A 9:16 screenshot, and a panorama.
    #expect(PhotoFrame.aspectRatio(of: try photos((1080, 1920))) == 0.8)
    #expect(PhotoFrame.aspectRatio(of: try photos((1080, 270))) == 1.91)
}

@Test func aCoverWithoutItsSizeKeepsTheLandscapeBox() throws {
    #expect(PhotoFrame.aspectRatio(of: try photos(nil, (1080, 1350))) == 1.5)
}
