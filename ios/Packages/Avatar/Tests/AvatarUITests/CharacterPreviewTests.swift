#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarUI
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers

/// Writes the placeholder character's previews for reviewers: stills of both outfits, a
/// strip of cheer frames, and the player's output frame by frame as animated GIFs.
/// Runs only when `AVATAR_PREVIEW_DIR` names a folder (`scripts/avatar-preview.sh` sets it),
/// so ordinary test runs stay fast.
@MainActor
struct CharacterPreviewTests {
    nonisolated static let folder = ProcessInfo.processInfo.environment["AVATAR_PREVIEW_DIR"].map {
        URL(fileURLWithPath: $0)
    }
    /// The design system's grouped background, so the figure sits on the app's neutral.
    static let mist = Color(.sRGB, red: 0xF3 / 255, green: 0xF5 / 255, blue: 0xF8 / 255, opacity: 1)
    static let fps = 50.0

    @Test(.enabled(if: CharacterPreviewTests.folder != nil)) func writePreviews() throws {
        let folder = try #require(Self.folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tee = try Frame(outfit: PlaceholderCharacter.tee)
        let hoodie = try Frame(outfit: PlaceholderCharacter.hoodie)
        let idle = try PlaceholderCharacter.clip("idle")
        let cheer = try PlaceholderCharacter.clip("cheer")

        try writePNG(
            [
                tee.render(image: tee.figure.restPose, scale: 2, background: Self.mist),
                hoodie.render(image: hoodie.figure.restPose, scale: 2, background: Self.mist),
            ],
            to: folder.appendingPathComponent("01-outfits.png"))

        let bound = try tee.figure.bind(cheer)
        let strip = try [0, 0.18, 0.3, 0.44, 0.6, 0.72, 0.95, 1.3].map { time in
            try tee.render(image: tee.figure.pose(bound, at: time), scale: 1, background: Self.mist)
        }
        try writePNG(strip, to: folder.appendingPathComponent("02-cheer-frames.png"))

        // What the player shows when someone checks in: idle, the cheer on top, back to idle.
        var performance = Performance(figure: tee.figure, idle: try tee.figure.bind(idle))
        performance.play(bound, at: 0.6)
        let cheerFrames = try frames(seconds: 3.2) { time in
            try tee.render(image: performance.pose(at: time), scale: 1, background: Self.mist)
        }
        try writeGIF(cheerFrames, to: folder.appendingPathComponent("03-check-in-cheer.gif"))

        let idleHoodie = Performance(figure: hoodie.figure, idle: try hoodie.figure.bind(idle))
        let idleFrames = try frames(seconds: idle.duration) { time in
            try hoodie.render(image: idleHoodie.pose(at: time), scale: 1, background: Self.mist)
        }
        try writeGIF(idleFrames, to: folder.appendingPathComponent("04-idle-hoodie.gif"))

        try writeTimings(tee, performance, to: folder.appendingPathComponent("timings.txt"))
    }

    private func frames(seconds: Double, _ render: (Double) throws -> CGImage) throws -> [CGImage] {
        try (0..<Int(seconds * Self.fps)).map { index in try render(Double(index) / Self.fps) }
    }

    /// Images side by side.
    private func writePNG(_ images: [CGImage], to url: URL) throws {
        let width = images.reduce(0) { $0 + $1.width }
        let height = images.map(\.height).max() ?? 0
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        var left = 0
        for image in images {
            context.draw(image, in: CGRect(x: left, y: height - image.height, width: image.width, height: image.height))
            left += image.width
        }
        let sheet = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, sheet, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func writeGIF(_ images: [CGImage], to url: URL) throws {
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, images.count, nil))
        let loopForever = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(destination, loopForever as CFDictionary)
        let delay = 1 / Self.fps
        let frame = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: delay, kCGImagePropertyGIFUnclampedDelayTime as String: delay,
            ]
        ]
        for image in images {
            CGImageDestinationAddImage(destination, image, frame as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
    }

    /// The cost of one frame: posing (pure math) and posing plus drawing at the phone's 3x
    /// into an offscreen bitmap, which is slower than drawing to the screen.
    private func writeTimings(_ frame: Frame, _ performance: Performance, to url: URL) throws {
        let count = 600
        let clock = ContinuousClock()
        let posing = clock.measure {
            for index in 0..<count {
                _ = frame.figure.layout(performance.pose(at: Double(index) / 120))
            }
        }
        let drawCount = 60
        let drawing = try clock.measure {
            for index in 0..<drawCount {
                _ = try frame.render(image: performance.pose(at: Double(index) / 60), scale: 3, background: .white)
            }
        }
        func milliseconds(_ duration: Duration, _ frames: Int) -> String {
            let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            return String(format: "%.3f ms", seconds * 1000 / Double(frames))
        }
        let report = """
            pose + layout per frame: \(milliseconds(posing, count)) (\(count) frames)
            pose + layout + draw at 3x into a bitmap per frame: \(milliseconds(drawing, drawCount)) (\(drawCount) frames)
            budget per frame: 16.7 ms at 60 Hz, 8.3 ms at 120 Hz
            """
        print(report)
        try report.write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
