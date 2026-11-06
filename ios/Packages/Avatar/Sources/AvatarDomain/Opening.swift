import Foundation

/// A full-screen opening an admin draws, such as a holiday's 「感恩节快乐」 (Tracy, 2026-11-04: art
/// she makes, never a template): layers of SVG art, words in each of the app's languages and the
/// member's own squad, placed on a stage and moved by one keyframe clip whose parts are the
/// layers' ids. It is data (`openings/<id>/timeline.json` beside its SVGs), so a new one reaches
/// installed apps without a release; what a layer can do is this type's to say.
public struct Opening: Hashable, Sendable {
    /// The only `version` of `timeline.json` this build reads.
    public static let currentVersion = 1

    public let name: String
    /// The stage the layers are placed on, in points; the screen fills with it, cropping its
    /// edges on a phone of another shape.
    public let stage: Size
    public let background: RGBAColor
    /// Drawn in order, the first at the back.
    public let layers: [Layer]
    /// What moves the layers, by their ids; it plays once.
    public let clip: Clip
    /// What keeps moving on top of it, from the start and for as long as the opening shows,
    /// such as leaves falling: x, y and rotation add to the clip's, scales and opacity multiply.
    public let loop: Clip?
    /// The 进场 button's colours, shown once the clip has played.
    public let button: ButtonColors

    public struct Size: Hashable, Sendable {
        public let width: Double
        public let height: Double
    }

    public struct ButtonColors: Hashable, Sendable {
        public let background: RGBAColor
        public let text: RGBAColor
    }

    /// A rectangle on the stage: its top left corner and size, in stage points.
    public struct Frame: Hashable, Sendable {
        // swiftlint:disable:next identifier_name - the stage's own coordinate names.
        public let x: Double, y: Double
        public let width: Double
        public let height: Double
    }

    public struct Layer: Hashable, Sendable {
        public let id: PartID
        public let content: Content
        /// Where it rests on the stage.
        public let frame: Frame
    }

    /// What a layer draws.
    public enum Content: Hashable, Sendable {
        /// An SVG beside `timeline.json`, by file name, fitted into the frame.
        case art(String)
        /// Words in each language (`zh-Hans`, `en`, `zh-Hant`), centred in the frame, in the
        /// app's display face (the wordmark's condensed one) or its body face.
        case text(words: [String: String], color: RGBAColor, size: Double, font: Font)
        /// The member's squad, cheering, along the frame's bottom edge.
        case squad
    }

    public enum Font: String, Hashable, Sendable {
        case display, body
    }

    /// Where a layer is at a moment of the clip: moved from its frame by `x` and `y`, turned by
    /// `rotation` degrees clockwise about its centre, scaled about its centre, and faded.
    public struct Placement: Hashable, Sendable {
        // swiftlint:disable:next identifier_name - x and y are the clip's own channel names.
        public var x: Double, y: Double, rotation: Double, scaleX: Double, scaleY: Double, opacity: Double

        /// Sets a channel to `value`, or, `onTop` (the loop over the clip), moves it further:
        /// x, y and rotation add, scales and opacity multiply.
        mutating func move(_ channel: Channel, by value: Double, onTop: Bool) {
            func add(_ current: inout Double) { current = onTop ? current + value : value }
            func multiply(_ current: inout Double) { current = onTop ? current * value : value }
            switch channel {
            case .x: add(&x)
            case .y: add(&y)
            case .rotation: add(&rotation)
            case .scaleX: multiply(&scaleX)
            case .scaleY: multiply(&scaleY)
            case .opacity: multiply(&opacity)
            case .bend: break
            }
        }
    }

    /// How `layer` stands `time` seconds in. Past the clip's end it holds its last pose.
    public func placement(of layer: PartID, at time: Double) -> Placement {
        var placement = Placement(x: 0, y: 0, rotation: 0, scaleX: 1, scaleY: 1, opacity: 1)
        for track in clip.tracks where track.part == layer {
            placement.move(track.channel, by: track.value(at: min(max(time, 0), clip.duration)), onTop: false)
        }
        if let loop {
            let looped = max(time, 0).truncatingRemainder(dividingBy: loop.duration)
            for track in loop.tracks where track.part == layer {
                placement.move(track.channel, by: track.value(at: looped), onTop: true)
            }
        }
        placement.opacity = min(max(placement.opacity, 0), 1)
        return placement
    }

    /// The SVG files its layers draw, by name.
    public var artFiles: [String] {
        layers.compactMap { if case .art(let file) = $0.content { file } else { nil } }
    }

    /// Reads `timeline.json`. Its `clip` and optional `loop` are clip files of their own
    /// (`version`, `name`, `duration`, `loops`, `tracks`) whose parts are layer ids: the clip
    /// plays once and the loop loops, and neither moves a `bend`.
    public static func decode(_ data: Data) throws(AvatarError) -> Opening {
        let file: OpeningFile = try decodeJSON(data, version: currentVersion, shape: OpeningFile.shape)
        let (clip, loop) = try clips(in: data, named: file.name)
        guard file.stage.width > 0, file.stage.height > 0 else { throw .malformedJSON("\(file.name): stage") }
        let ids = file.layers.map(\.id)
        guard Set(ids).count == ids.count else { throw .malformedJSON("\(file.name): a layer id is used twice") }
        for track in clip.tracks + (loop?.tracks ?? []) where !ids.contains(track.part) {
            throw .unknownPart(clip: file.name, part: track.part)
        }
        var layers: [Layer] = []
        for layer in file.layers { layers.append(try Layer(layer, in: file.name)) }
        return Opening(
            name: file.name, stage: Size(width: file.stage.width, height: file.stage.height),
            background: try color(file.background, in: file.name), layers: layers, clip: clip, loop: loop,
            button: ButtonColors(
                background: try color(file.button.background, in: file.name),
                text: try color(file.button.text, in: file.name)))
    }

    /// The clip, which plays once, and the loop, if any, which loops; neither bends.
    private static func clips(in data: Data, named name: String) throws(AvatarError) -> (Clip, Clip?) {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        func clip(_ key: String) throws(AvatarError) -> Clip? {
            guard let value = object?[key] else { return nil }
            guard let clipData = try? JSONSerialization.data(withJSONObject: value) else {
                throw .malformedJSON("\(name): \(key)")
            }
            return try Clip.decode(clipData)
        }
        guard let once = try clip("clip") else { throw .malformedJSON("\(name): clip") }
        let loop = try clip("loop")
        guard !once.loops, loop?.loops ?? true, (once.tracks + (loop?.tracks ?? [])).allSatisfy({ $0.channel != .bend })
        else {
            throw .malformedJSON("\(name): an opening's clip plays once, its loop loops, and neither bends")
        }
        return (once, loop)
    }

    fileprivate static func color(_ text: String, in name: String) throws(AvatarError) -> RGBAColor {
        guard let color = RGBAColor(hex: text) else { throw .malformedJSON("\(name): colour \(text)") }
        return color
    }
}

extension Opening.Layer {
    /// A layer as `timeline.json` gives it: exactly one of art (a bare `.svg` name), words (with
    /// `zh-Hans` and a size) or the squad, and a size.
    fileprivate init(_ layer: OpeningFile.LayerFile, in name: String) throws(AvatarError) {
        let kinds = [layer.art != nil, layer.text != nil, layer.squad == true].filter { $0 }.count
        guard kinds == 1, layer.width > 0, layer.height > 0 else {
            throw .malformedJSON("\(name): layer \(layer.id) needs one of art, text or squad, and a size")
        }
        let content: Opening.Content
        if let art = layer.art {
            guard art.hasSuffix(".svg"), !art.contains("/"), !art.hasPrefix(".") else {
                throw .malformedJSON("\(name): layer \(layer.id) art \(art)")
            }
            content = .art(art)
        } else if let text = layer.text {
            guard text.words["zh-Hans"] != nil, let size = text.size, size > 0,
                let font = Opening.Font(rawValue: text.font ?? Opening.Font.body.rawValue)
            else {
                throw .malformedJSON("\(name): layer \(layer.id) needs zh-Hans words, a size and a known font")
            }
            content = .text(words: text.words, color: try Opening.color(text.color, in: name), size: size, font: font)
        } else {
            content = .squad
        }
        self.init(
            id: layer.id, content: content,
            frame: Opening.Frame(x: layer.x, y: layer.y, width: layer.width, height: layer.height))
    }
}

private struct OpeningFile: Decodable {
    let name: String
    let stage: Stage
    let background: String
    let button: Button
    let layers: [LayerFile]

    struct Stage: Decodable {
        let width: Double
        let height: Double
    }

    struct Button: Decodable {
        let background: String
        let text: String
    }

    struct LayerFile: Decodable {
        let id: PartID
        // swiftlint:disable:next identifier_name - the stage's own coordinate names.
        let x: Double, y: Double
        let width: Double
        let height: Double
        let art: String?
        let text: TextFile?
        let squad: Bool?
    }

    struct TextFile: Decodable {
        let words: [String: String]
        let color: String
        let size: Double?
        let font: String?
    }

    /// The clip is checked by `Clip.decode` itself.
    static let shape = JSONShape.object([
        "version": .value, "name": .value, "background": .value, "clip": .value, "loop": .value,
        "stage": .object(["width": .value, "height": .value]),
        "button": .object(["background": .value, "text": .value]),
        "layers": .array(
            .object([
                "id": .value, "x": .value, "y": .value, "width": .value, "height": .value, "art": .value,
                "squad": .value,
                "text": .object(["words": .value, "color": .value, "size": .value, "font": .value]),
            ])),
    ])
}
