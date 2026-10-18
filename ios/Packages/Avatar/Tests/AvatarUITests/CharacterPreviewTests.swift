#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarUI
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers

/// Writes the placeholder characters' previews for reviewers: stills of the four looks, a
/// strip of each persona's cheer, the five cheering together as the player shows it, each
/// persona's idle loop, frame by frame as animated GIFs, and a sheet of the color swatches.
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
        let squad = try PlaceholderCharacter.squad.map { outfit in try Frame(outfit: outfit) }
        try writePNG(
            sideBySide(
                squad.map { look in try look.render(image: look.figure.restPose, scale: 2, background: Self.mist) }),
            to: folder.appendingPathComponent("01-outfits.png"))

        // One character per persona, the looks taking turns.
        let cast = Persona.allCases.indices.map { squad[$0 % squad.count] }
        let idles = try zip(Persona.allCases, cast).map { persona, look in
            try look.figure.bind(PlaceholderCharacter.clip("idle", persona: persona))
        }
        let cheers = try zip(Persona.allCases, cast).map { persona, look in
            try look.figure.bind(PlaceholderCharacter.clip("cheer", persona: persona))
        }

        // Each persona's cheer as a row of frames, one row per persona.
        let rows = try zip(cast, cheers).map { look, cheer in
            try sideBySide(
                (0..<6).map { step in
                    let time = cheer.clip.duration * Double(step) / 5
                    return try look.render(image: look.figure.pose(cheer, at: time), scale: 1, background: Self.mist)
                })
        }
        try writePNG(stacked(rows), to: folder.appendingPathComponent("02-cheer-frames.png"))

        // What the player shows when the five check in together: idle, the cheer on top,
        // back to idle.
        var performances: [Performance] = []
        for (index, look) in cast.enumerated() {
            var performance = Performance(figure: look.figure, idle: idles[index])
            performance.play(cheers[index], at: 0.6)
            performances.append(performance)
        }
        try writeGIF(
            frames(seconds: 4) { time in
                try sideBySide(
                    zip(cast, performances).map { look, performance in
                        try look.render(image: performance.pose(at: time), scale: 1, background: Self.mist)
                    })
            },
            to: folder.appendingPathComponent("03-check-in-cheer.gif"))

        // Each persona's idle on its own, exactly one loop long, so the GIF repeats seamlessly.
        for (persona, (look, idle)) in zip(Persona.allCases, zip(cast, idles)) {
            try writeGIF(
                frames(seconds: idle.clip.duration) { time in
                    try look.render(image: look.figure.pose(idle, at: time), scale: 1, background: Self.mist)
                },
                to: folder.appendingPathComponent("04-idle-\(persona.rawValue).gif"))
        }

        try writeSwatches(to: folder.appendingPathComponent("05-swatches.png"))

        try writeTimings(cast[0], performances[0], to: folder.appendingPathComponent("timings.txt"))
    }

    /// The editor's swatches: a row per slot, a look in every color the slot offers.
    private func writeSwatches(to url: URL) throws {
        let rows: [(Outfit, Slot)] = [
            (PlaceholderCharacter.lifter, "body"), (PlaceholderCharacter.lifter, "hair"),
            (PlaceholderCharacter.lifter, "top"), (PlaceholderCharacter.lifter, "bottom"),
            (PlaceholderCharacter.cat, "body"), (PlaceholderCharacter.bear, "body"),
        ]
        let sheet = try rows.map { outfit, slot in
            let variant = try #require(outfit.variants[slot])
            return try sideBySide(
                PlaceholderCharacter.swatches(for: slot, wearing: variant).map { swatch in
                    var colored = outfit
                    colored.colors[slot] = swatch
                    let look = try Frame(outfit: colored)
                    return try look.render(image: look.figure.restPose, scale: 1, background: Self.mist)
                })
        }
        try writePNG(stacked(sheet), to: url)
    }

    private func frames(seconds: Double, _ render: (Double) throws -> CGImage) throws -> [CGImage] {
        try (0..<Int((seconds * Self.fps).rounded())).map { index in try render(Double(index) / Self.fps) }
    }

    /// Images side by side, as one image.
    private func sideBySide(_ images: [CGImage]) throws -> CGImage {
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
        return try #require(context.makeImage())
    }

    /// Images one above the other, as one image.
    private func stacked(_ images: [CGImage]) throws -> CGImage {
        let width = images.map(\.width).max() ?? 0
        let height = images.reduce(0) { $0 + $1.height }
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Core Graphics counts rows from the bottom, so the first image goes on top.
        var top = height
        for image in images {
            top -= image.height
            context.draw(image, in: CGRect(x: 0, y: top, width: image.width, height: image.height))
        }
        return try #require(context.makeImage())
    }

    private func writePNG(_ sheet: CGImage, to url: URL) throws {
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
        // End with a newline, so `cat` in the preview log doesn't run into the next line.
        try (report + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
