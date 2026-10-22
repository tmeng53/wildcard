#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarLooks
@testable import AvatarUI
import Contracts
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
        let lifter = try Frame(outfit: PlaceholderCharacter.lifter)
        let image = try lifter.render(lifter.figure.restPose)
        // The middle of the face, the outer dumbbell plate in the right hand, and empty canvas.
        #expect(matches(image.color(atColumn: 120, row: 150), Self.skin))
        #expect(matches(image.color(atColumn: 193, row: 255), Self.plate))
        #expect(matches(image.color(atColumn: 10, row: 10), Self.white))

        // The bear has no prop: the same spot, past the hand, is empty.
        let bear = try Frame(outfit: Looks.bear)
        #expect(matches(try bear.render(bear.figure.restPose).color(atColumn: 193, row: 255), Self.white))
    }

    @Test func theCheerCarriesTheDumbbellUpWithTheArm() throws {
        let lifter = try Frame(outfit: PlaceholderCharacter.lifter)
        let cheer = try lifter.figure.bind(PlaceholderCharacter.clip("cheer", persona: .energetic))
        // The top of the energetic cheer's second jump, arms overhead.
        let peak = lifter.figure.pose(cheer, at: 0.84)
        let image = try lifter.render(peak)
        // The plate's rest spot is empty, and the plate is where the arm and prop transforms take it.
        #expect(matches(image.color(atColumn: 193, row: 255), Self.white))
        let prop = try #require(lifter.figure.parts.firstIndex { $0.id == "propR" })
        let moved = lifter.figure.layout(peak)[prop].transform.apply(to: Point(x: 193, y: 255))
        #expect(matches(image.color(atColumn: Int(moved.x.rounded()), row: Int(moved.y.rounded())), Self.plate))
    }

    /// Picking a sport: the player draws the old clothes until the hop's squash, the kit after.
    @Test func thePlayerSwapsTheKitInMidHop() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let lifter = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
        let player = try CharacterPlayer(
            figure: lifter, idle: PlaceholderCharacter.clip("idle", persona: .shy), now: start)
        let swim = try PlaceholderCharacter.sportKits().kit(for: .sport(.swim))
        let swimmer = try PlaceholderCharacter.figure(wearing: swim.dress(PlaceholderCharacter.lifter))
        let hop = try PlaceholderCharacter.kitHop()
        try player.change(
            into: swimmer, idle: PlaceholderCharacter.move(for: swim, persona: .shy), hop: hop,
            now: start.addingTimeInterval(1))
        let before = player.frame(at: start.addingTimeInterval(1 + hop.out.duration / 2))
        let after = player.frame(at: start.addingTimeInterval(1 + hop.out.duration + 0.01))
        let hat = try #require(swimmer.parts.firstIndex { $0.id == "crown" })
        #expect(before.drawing.width == after.drawing.width)
        #expect(lifter.parts[hat].art.isEmpty && !swimmer.parts[hat].art.isEmpty)
        #expect(player.figure == swimmer)
        // Reduce Motion shows the kit straight away, standing still.
        #expect(player.restFrame.placements == swimmer.layout(swimmer.restPose))
    }

    /// Taking a sport off mid-hop: the outfit worn instead stays on, the kit never shows.
    @Test func wearingMidHopDropsTheKit() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let lifter = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
        let idle = try PlaceholderCharacter.clip("idle", persona: .shy)
        let player = try CharacterPlayer(figure: lifter, idle: idle, now: start)
        let swim = try PlaceholderCharacter.sportKits().kit(for: .sport(.swim))
        let swimmer = try PlaceholderCharacter.figure(wearing: swim.dress(PlaceholderCharacter.lifter))
        try player.change(
            into: swimmer, idle: PlaceholderCharacter.move(for: swim, persona: .shy),
            hop: PlaceholderCharacter.kitHop(), now: start.addingTimeInterval(1))
        try player.wear(lifter, idle: idle, now: start.addingTimeInterval(1.05))
        let later = player.frame(at: start.addingTimeInterval(2))
        let hat = try #require(swimmer.parts.firstIndex { $0.id == "crown" })
        // The swim cap is drawn only in the kit.
        #expect(lifter.parts[hat].art.isEmpty && !swimmer.parts[hat].art.isEmpty)
        #expect(later.drawing.parts[hat].isEmpty)
        #expect(player.restFrame.drawing.parts[hat].isEmpty)
        #expect(player.figure == lifter)
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

    /// `crop`, in canvas points, draws that area instead of the canvas, as for the 上场 stage.
    func render(image pose: Pose, scale: Double, background: Color, crop: CGRect? = nil) throws -> CGImage {
        let view = CharacterCanvas(drawing: drawing, placements: figure.layout(pose), crop: crop)
            .frame(width: crop?.width ?? drawing.width, height: crop?.height ?? drawing.height)
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
