#if canImport(ImageIO)
import CheckInDomain
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shrinks a picked photo before it goes anywhere: at most 1080 px on the long edge, JPEG at
/// quality 0.7, so a check-in photo is a few hundred KB and the free storage tier lasts.
/// Runs off the main actor: decoding a camera photo takes long enough to drop frames.
public enum PhotoPreparation {
    public static let maxPixelSize = 1080
    public static let jpegQuality = 0.7

    /// Decodes `data` (HEIC, JPEG, PNG…), downsamples it and re-encodes it as JPEG.
    public nonisolated static func prepare(_ data: Data) async throws(CheckInError) -> PreparedPhoto {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw .unreadablePhoto
        }
        let thumbnailOptions =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw .unreadablePhoto
        }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw .unreadablePhoto }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw .unreadablePhoto }
        return PreparedPhoto(id: UUID(), jpeg: output as Data)
    }
}
#endif
