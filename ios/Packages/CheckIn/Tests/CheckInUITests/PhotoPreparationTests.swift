#if canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CheckInUI

/// A 40 × 20 JPEG tagged as taken in Manhattan on an iPhone, rotated a quarter turn (orientation 6).
private func taggedPhoto() throws -> Data {
    let context = try #require(
        CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
    let image = try #require(context.makeImage())
    let output = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
    let properties: [CFString: Any] = [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 40.7484, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 73.9857, kCGImagePropertyGPSLongitudeRef: "W",
        ],
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: "2026:10:31 08:00:00",
            kCGImagePropertyExifLensModel: "iPhone back camera",
        ],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"],
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

private func properties(of data: Data) throws -> [CFString: Any] {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
}

@Suite struct PhotoPreparationTests {
    @Test func theUploadedCopyCarriesNoLocationOrCameraData() async throws {
        let original = try taggedPhoto()
        // The fixture really is tagged, so the checks below can fail.
        #expect(try properties(of: original)[kCGImagePropertyGPSDictionary] != nil)

        let prepared = try await PhotoPreparation.prepare(original)
        let kept = try properties(of: prepared.jpeg)
        #expect(kept[kCGImagePropertyGPSDictionary] == nil)
        let exif = kept[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect(exif[kCGImagePropertyExifLensModel] == nil)
        let tiff = kept[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff[kCGImagePropertyTIFFModel] == nil)
        // The quarter turn is in the pixels now, not in a tag.
        #expect((kept[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        #expect(prepared.size?.width == 20)
        #expect(prepared.size?.height == 40)
    }
}
#endif
