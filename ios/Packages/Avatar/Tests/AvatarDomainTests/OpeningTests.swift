import Foundation
import Testing

@testable import AvatarDomain

// An opening's timeline: layers on a stage moved by a clip that plays once, with a loop on
// top that keeps going, and refused when it names art, parts or colours it can't draw.

private func timeline(layers: String? = nil, clip: String? = nil, loop: String? = nil) -> Data {
    let layers =
        layers ?? """
            [{"id": "leaves", "x": 0, "y": -100, "width": 390, "height": 1000, "art": "leaves.svg"},
             {"id": "title", "x": 20, "y": 300, "width": 350, "height": 70,
              "text": {"words": {"zh-Hans": "感恩节快乐", "en": "Happy Thanksgiving"}, "color": "#FFFFFF",
                       "size": 48, "font": "display"}},
             {"id": "squad", "x": 10, "y": 520, "width": 370, "height": 190, "squad": true}]
            """
    let clip =
        clip ?? """
            {"version": 1, "name": "in", "duration": 2, "loops": false, "tracks": [
              {"part": "title", "channel": "opacity", "keys": [{"t": 0, "v": 0}, {"t": 1, "v": 1}]},
              {"part": "leaves", "channel": "x", "keys": [{"t": 0, "v": 10}, {"t": 2, "v": 10}]}]}
            """
    let loop = loop.map { #", "loop": \#($0)"# } ?? ""
    return Data(
        """
        {"version": 1, "name": "Thanksgiving", "stage": {"width": 390, "height": 844}, "background": "#A8521F",
         "button": {"background": "#FFFFFF", "text": "#A8521F"}, "layers": \(layers), "clip": \(clip)\(loop)}
        """.utf8)
}

private let falling = """
    {"version": 1, "name": "fall", "duration": 4, "loops": true, "tracks": [
      {"part": "leaves", "channel": "y", "keys": [{"t": 0, "v": 0}, {"t": 4, "v": 400}]},
      {"part": "title", "channel": "opacity", "keys": [{"t": 0, "v": 0.5}, {"t": 4, "v": 0.5}]}]}
    """

@Test func readsAnOpeningsLayersAndTheirPlaces() throws {
    let opening = try Opening.decode(timeline())
    #expect(opening.name == "Thanksgiving")
    #expect(opening.stage == Opening.Size(width: 390, height: 844))
    #expect(opening.artFiles == ["leaves.svg"])
    #expect(opening.layers.map(\.id) == ["leaves", "title", "squad"])
    #expect(opening.layers[2].content == .squad)
    #expect(opening.layers[0].frame == Opening.Frame(x: 0, y: -100, width: 390, height: 1000))
    guard case .text(let words, let color, let size, let font) = opening.layers[1].content else {
        Issue.record("the title is words")
        return
    }
    #expect(words["en"] == "Happy Thanksgiving")
    #expect(color.hex == "#FFFFFF")
    #expect(size == 48)
    #expect(font == .display)
    #expect(opening.button.text.hex == "#A8521F")
}

@Test func theClipPlaysOnceAndHoldsItsLastPose() throws {
    let opening = try Opening.decode(timeline())
    #expect(opening.placement(of: "title", at: 0).opacity == 0)
    #expect(opening.placement(of: "title", at: 0.5).opacity == 0.5)
    #expect(opening.placement(of: "title", at: 30).opacity == 1)
    #expect(opening.placement(of: "squad", at: 1) == .init(x: 0, y: 0, rotation: 0, scaleX: 1, scaleY: 1, opacity: 1))
}

@Test func theLoopKeepsGoingOnTopOfTheClip() throws {
    let opening = try Opening.decode(timeline(loop: falling))
    // x comes from the clip, y from the loop, which starts again every 4 seconds.
    #expect(opening.placement(of: "leaves", at: 1).x == 10)
    #expect(opening.placement(of: "leaves", at: 1).y == 100)
    #expect(opening.placement(of: "leaves", at: 5).y == 100)
    // Opacities multiply.
    #expect(opening.placement(of: "title", at: 30).opacity == 0.5)
}

@Test func refusesAClipThatLoopsOrALoopThatDoesnt() {
    let looping = """
        {"version": 1, "name": "in", "duration": 2, "loops": true, "tracks": []}
        """
    #expect(throws: AvatarError.self) { try Opening.decode(timeline(clip: looping)) }
    let once = falling.replacingOccurrences(of: #""loops": true"#, with: #""loops": false"#)
    #expect(throws: AvatarError.self) { try Opening.decode(timeline(loop: once)) }
}

@Test func refusesAPartNoLayerHas() {
    let stray = falling.replacingOccurrences(of: #""part": "leaves""#, with: #""part": "snow""#)
    #expect(throws: AvatarError.unknownPart(clip: "Thanksgiving", part: "snow")) {
        try Opening.decode(timeline(loop: stray))
    }
}

@Test(arguments: [
    ##"[{"id": "a", "x": 0, "y": 0, "width": 1, "height": 1, "art": "../a.svg"}]"##,
    ##"[{"id": "a", "x": 0, "y": 0, "width": 1, "height": 1, "art": "a.png"}]"##,
    ##"[{"id": "a", "x": 0, "y": 0, "width": 1, "height": 1}]"##,
    ##"[{"id": "a", "x": 0, "y": 0, "width": 0, "height": 1, "squad": true}]"##,
    ##"[{"id": "a", "x": 0, "y": 0, "width": 1, "height": 1, "squad": true, "art": "a.svg"}]"##,
    ##"[{"id": "a", "x": 0, "y": 0, "width": 1, "height": 1, "squad": true}, {"id": "a", "x": 0, "y": 0, "width": 1, "height": 1, "squad": true}]"##,
    ##"[{"id": "a", "x": 0, "y": 0, "width": 1, "height": 1, "text": {"words": {"en": "Hi"}, "color": "#FFFFFF", "size": 9}}]"##,
    ##"[{"id": "a", "x": 0, "y": 0, "width": 1, "height": 1, "text": {"words": {"zh-Hans": "嗨"}, "color": "white", "size": 9}}]"##,
    ##"[{"id": "a", "x": 0, "y": 0, "width": 1, "height": 1, "text": {"words": {"zh-Hans": "嗨"}, "color": "#FFFFFF", "size": 9, "font": "comic"}}]"##,
    ##"[{"id": "a", "x": 0, "y": 0, "width": 1, "height": 1, "squad": true, "glow": true}]"##,
])
func refusesALayerItCantDraw(layers: String) {
    let still = #"{"version": 1, "name": "in", "duration": 1, "loops": false, "tracks": []}"#
    #expect(throws: AvatarError.self) { try Opening.decode(timeline(layers: layers, clip: still)) }
}
