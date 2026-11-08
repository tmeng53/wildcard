import CheckInDomain
import Testing

@Test func aPortraitPhotoGoesUp1080Wide() {
    // An iPhone's 3024 × 4032 portrait photo: 1080 × 1440.
    #expect(PhotoUploadSize.longEdge(width: 3024, height: 4032) == 1440)
}

@Test func aLandscapePhotoGoesUp1080Tall() {
    #expect(PhotoUploadSize.longEdge(width: 4032, height: 3024) == 1440)
}

@Test func aTallPhotoStopsAt1920() {
    // 9:16 is 1080 × 1920; a 1:2 screenshot is held to 1920 tall.
    #expect(PhotoUploadSize.longEdge(width: 2160, height: 3840) == 1920)
    #expect(PhotoUploadSize.longEdge(width: 1170, height: 2532) == 1920)
}

@Test func aSmallPhotoIsNeverEnlarged() {
    #expect(PhotoUploadSize.longEdge(width: 800, height: 600) == 800)
    #expect(PhotoUploadSize.longEdge(width: 40, height: 20) == 40)
}

@Test func aPhotoOfUnknownSizeGoesUpAsBefore() {
    #expect(PhotoUploadSize.longEdge(width: 0, height: 0) == 1080)
}
