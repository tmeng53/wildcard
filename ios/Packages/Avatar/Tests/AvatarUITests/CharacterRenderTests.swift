#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarUI
import CoreGraphics
import Foundation
import SwiftUI
import Testing

/// Draws frames through the same `CharacterCanvas` the player uses and reads pixels back.
@MainActor
struct CharacterRenderTests {
    static let skin = (0xF5, 0xCD, 0xAE)
    static let plate = (0x1F, 0x21, 0x28)
    static let white = (0xFF, 0xFF, 0xFF)

    @Test func drawsTheRestPoseWhereTheArtSays() throws {
        let tee = try Frame(outfit: PlaceholderCharacter.tee)
        let image = try tee.render(tee.figure.restPose)
        // The middle of the face, a dumbbell plate in the right hand, and empty canvas.
        #expect(matches(image.color(atColumn: 120, row: 112), Self.skin))
        #expect(matches(image.color(atColumn: 139, row: 229), Self.plate))
        #expect(matches(image.color(atColumn: 10, row: 10), Self.white))

        // The hoodie outfit has no prop: the same spot is empty.
        let hoodie = try Frame(outfit: PlaceholderCharacter.hoodie)
        #expect(matches(try hoodie.render(hoodie.figure.restPose).color(atColumn: 139, row: 229), Self.white))
    }

    @Test func theCheerCarriesTheDumbbellUpWithTheArm() throws {
        let tee = try Frame(outfit: PlaceholderCharacter.tee)
        let cheer = try tee.figure.bind(PlaceholderCharacter.clip("cheer"))
        let peak = tee.figure.pose(cheer, at: 0.44)
        let image = try tee.render(peak)
        // The plate's rest spot is empty, and the plate is where the arm's transform takes it.
        #expect(matches(image.color(atColumn: 139, row: 229), Self.white))
        let moved = tee.figure.layout(peak)[8].transform.apply(to: Point(x: 139, y: 229))
        #expect(matches(image.color(atColumn: Int(moved.x.rounded()), row: Int(moved.y.rounded())), Self.plate))
    }
}

/// One outfit's figure and a way to draw a pose of it at the canvas's own size.
@MainActor
struct Frame {
    let figure: Figure
    let drawing: FigureDrawing

    init(outfit: Outfit) throws {
        figure = try PlaceholderCharacter.figure(wearing: outfit)
        drawing = FigureDrawing(figure)
    }

    func render(_ pose: Pose, scale: Double = 1, background: Color = .white) throws -> Bitmap {
        try Bitmap(render(image: pose, scale: scale, background: background))
    }

    func render(image pose: Pose, scale: Double, background: Color) throws -> CGImage {
        let view = CharacterCanvas(drawing: drawing, placements: figure.layout(pose))
            .frame(width: drawing.width, height: drawing.height)
            .background(background)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return try #require(renderer.cgImage)
    }
}

/// An image redrawn into 8-bit sRGB so pixels can be compared with art colors.
struct Bitmap {
    let width: Int
    let bytes: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        self.bytes = bytes
    }

    /// (red, green, blue) at a pixel, rows counted from the top.
    func color(atColumn column: Int, row: Int) -> (Int, Int, Int) {
        let offset = (row * width + column) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }
}

/// Close enough to survive antialiasing and color conversion, far enough apart to tell
/// skin from dumbbell from background.
func matches(_ pixel: (Int, Int, Int), _ art: (Int, Int, Int)) -> Bool {
    abs(pixel.0 - art.0) <= 6 && abs(pixel.1 - art.1) <= 6 && abs(pixel.2 - art.2) <= 6
}
#endif
