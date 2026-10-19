import Foundation

/// Where the art files live, as `base/<art>.svg` or `<slot>/<variant>/<art>.svg`, with a
/// variant's `tones.json` beside its art. An adapter reads them from the app bundle; tests
/// pass strings.
public protocol ArtSource {
    /// The file's text, or nil when there is no such file.
    func text(at path: String) -> String?
}

/// Which variant each slot wears, such as `top: tee` and `prop: dumbbell`, and the color
/// a slot is recolored to, if any. A slot left out wears the rig's default for it, or
/// nothing; a slot with no color keeps its art's own.
public struct Outfit: Hashable, Sendable {
    public var variants: [Slot: String]
    /// The new main color per slot. The variant's `tones.json` says which of its art's
    /// colors follow it.
    public var colors: [Slot: RGBAColor]

    public init(_ variants: [Slot: String], colors: [Slot: RGBAColor] = [:]) {
        (self.variants, self.colors) = (variants, colors)
    }
}

/// A character in one outfit, ready to pose: the rig with every part's art read and
/// parsed once, so posing and drawing a frame does no parsing or file work.
public struct Figure: Hashable, Sendable {
    public let width: Double
    public let height: Double
    /// Back to front.
    public let parts: [Part]
    /// Each part's parent, as an index into `parts`.
    let parents: [Int?]
    /// Part indices with every parent before its children.
    let evaluationOrder: [Int]

    public struct Part: Hashable, Sendable {
        public let id: PartID
        public let pivot: Point
        public let restOpacity: Double
        /// Back to front.
        public let art: [Artwork]
    }

    public init(rig: Rig, outfit: Outfit, art source: some ArtSource) throws(AvatarError) {
        let parents = try Self.parents(rig.parts)
        evaluationOrder = try Self.order(rig.parts.map(\.id), parents)

        // What the outfit picks, and the rig's default for each slot it leaves out.
        let variants = rig.defaults.merging(outfit.variants) { _, picked in picked }
        let recolors = try Self.recolors(variants, outfit.colors, source)

        var used: Set<Slot> = []
        /// Each recolored slot's art colors before recoloring, to check its tones against.
        var painted: [Slot: [RGBAColor]] = [:]
        var built: [Part] = []
        for part in rig.parts {
            var artworks: [Artwork] = []
            for layer in part.layers {
                let path: String
                if let slot = layer.slot {
                    guard let variant = variants[slot] else { continue }
                    path = "\(slot)/\(variant)/\(layer.art).svg"
                    // A variant may leave a part bare, like a tank top with no sleeves.
                    guard let svg = source.text(at: path) else { continue }
                    var artwork = try Self.artwork(svg, path, rig)
                    if let recolor = recolors[slot] {
                        painted[slot, default: []] += artwork.colors
                        artwork = recolor.applied(to: artwork)
                    }
                    artworks.append(artwork)
                    used.insert(slot)
                } else {
                    path = "base/\(layer.art).svg"
                    guard let svg = source.text(at: path) else { throw .missingArt(path) }
                    artworks.append(try Self.artwork(svg, path, rig))
                }
            }
            built.append(Part(id: part.id, pivot: part.pivot, restOpacity: part.opacity, art: artworks))
        }
        if let (slot, variant) = variants.first(where: { !used.contains($0.key) }) {
            throw .unknownVariant(slot: slot, variant: variant)
        }
        try Self.checkTones(recolors, against: painted, variants)
        (width, height, parts, self.parents) = (rig.width, rig.height, built, parents)
    }

    /// Each colored slot's tones, read from its variant's `tones.json`.
    private static func recolors(
        _ variants: [Slot: String], _ colors: [Slot: RGBAColor], _ source: some ArtSource
    ) throws(AvatarError) -> [Slot: Recolor] {
        var recolors: [Slot: Recolor] = [:]
        for (slot, color) in colors.sorted(by: { $0.key.description < $1.key.description }) {
            guard let variant = variants[slot] else { throw .colorForBareSlot(slot) }
            guard let text = source.text(at: "\(slot)/\(variant)/tones.json") else {
                throw .notRecolorable(slot: slot, variant: variant)
            }
            let tones: Tones
            do {
                tones = try Tones.decode(Data(text.utf8))
            } catch .malformedJSON(let problem) {
                throw .malformedJSON("\(slot)/\(variant)/tones.json\(problem)")
            }
            recolors[slot] = Recolor(tones: tones, color: color)
        }
        return recolors
    }

    /// A tone the art never paints is a typo in `tones.json`, which would leave that color
    /// unchanged on the phone.
    private static func checkTones(
        _ recolors: [Slot: Recolor], against painted: [Slot: [RGBAColor]], _ variants: [Slot: String]
    ) throws(AvatarError) {
        for (slot, recolor) in recolors {
            let colors = painted[slot, default: []]
            if let unused = recolor.tones.all.first(where: { tone in !colors.contains { $0.sameRGB(as: tone) } }) {
                throw .unusedTone(slot: slot, variant: variants[slot] ?? "", color: unused)
            }
        }
    }

    /// Each part's parent as an index into the parts.
    private static func parents(_ parts: [Rig.Part]) throws(AvatarError) -> [Int?] {
        var index: [PartID: Int] = [:]
        for (position, part) in parts.enumerated() {
            guard index.updateValue(position, forKey: part.id) == nil else { throw .duplicatePart(part.id) }
        }
        return try parts.map { part throws(AvatarError) in
            guard let parent = part.parent else { return nil }
            guard let parentIndex = index[parent] else { throw .unknownParent(part: part.id, parent: parent) }
            return parentIndex
        }
    }

    /// Parents before children; a part that is its own ancestor is an error.
    private static func order(_ ids: [PartID], _ parents: [Int?]) throws(AvatarError) -> [Int] {
        var order: [Int] = []
        var state = [UInt8](repeating: 0, count: ids.count)  // 0 new, 1 visiting, 2 done
        for start in ids.indices where state[start] == 0 {
            var chain: [Int] = []
            var node: Int? = start
            while let current = node, state[current] != 2 {
                if state[current] == 1 { throw .parentCycle(ids[current]) }
                state[current] = 1
                chain.append(current)
                node = parents[current]
            }
            for part in chain.reversed() {
                state[part] = 2
                order.append(part)
            }
        }
        return order
    }

    private static func artwork(_ svg: String, _ path: String, _ rig: Rig) throws(AvatarError) -> Artwork {
        let artwork: Artwork
        do {
            artwork = try Artwork(svg: svg)
        } catch {
            throw .invalidSVG(art: path, problem: error)
        }
        guard artwork.width == rig.width, artwork.height == rig.height else { throw .canvasMismatch(art: path) }
        return artwork
    }

    /// Every part at rest.
    public var restPose: Pose {
        Pose(parts: parts.map { PartPose(opacity: $0.restOpacity) })
    }

    /// Checks that a clip only moves parts this figure has, and links its tracks to them.
    public func bind(_ clip: Clip) throws(AvatarError) -> BoundClip {
        var tracks: [(part: Int, track: Clip.Track)] = []
        for track in clip.tracks {
            guard let part = parts.firstIndex(where: { $0.id == track.part }) else {
                throw .unknownPart(clip: clip.name, part: track.part)
            }
            tracks.append((part, track))
        }
        return BoundClip(clip: clip, tracks: tracks)
    }

    /// The pose a clip gives at a time, counted from the clip's start. A looping clip wraps
    /// around; a one-shot clip holds its last frame.
    public func pose(_ bound: BoundClip, at time: Double) -> Pose {
        let clip = bound.clip
        let local: Double
        if clip.loops {
            let wrapped = time.truncatingRemainder(dividingBy: clip.duration)
            local = wrapped < 0 ? wrapped + clip.duration : wrapped
        } else {
            local = min(max(time, 0), clip.duration)
        }
        var pose = restPose
        for (part, track) in bound.tracks {
            pose.parts[part][track.channel] = track.value(at: local)
        }
        return pose
    }

    /// Where every part lands for a pose, back to front, in canvas coordinates.
    public func layout(_ pose: Pose) -> [Placement] {
        var placements = [Placement](repeating: Placement(transform: .identity, opacity: 1), count: parts.count)
        for index in evaluationOrder {
            let part = parts[index]
            let move = pose.parts[index]
            // Turn and scale around the pivot, then shift by the clip's offset.
            let local = Transform.translation(x: -part.pivot.x, y: -part.pivot.y)
                .then(.scale(x: move.scaleX, y: move.scaleY))
                .then(.rotation(degrees: move.rotation))
                .then(.translation(x: part.pivot.x + move.x, y: part.pivot.y + move.y))
            if let parent = parents[index] {
                let carrier = placements[parent]
                placements[index] = Placement(
                    transform: local.then(carrier.transform), opacity: move.opacity * carrier.opacity)
            } else {
                placements[index] = Placement(transform: local, opacity: move.opacity)
            }
        }
        return placements
    }
}

/// A clip linked to a figure's parts.
public struct BoundClip: Sendable {
    public let clip: Clip
    let tracks: [(part: Int, track: Clip.Track)]
}

/// One part's channel values. Unlike a clip, a pose has every channel of every part.
public struct PartPose: Hashable, Sendable {
    public var rotation = 0.0
    // swiftlint:disable:next identifier_name - the channel's name.
    public var x = 0.0
    public var y = 0.0
    public var scaleX = 1.0
    public var scaleY = 1.0
    public var opacity = 1.0

    public init(opacity: Double = 1) {
        self.opacity = opacity
    }

    public subscript(channel: Channel) -> Double {
        get {
            switch channel {
            case .rotation: rotation
            case .x: x
            case .y: y
            case .scaleX: scaleX
            case .scaleY: scaleY
            case .opacity: opacity
            }
        }
        set {
            switch channel {
            case .rotation: rotation = newValue
            case .x: x = newValue
            case .y: y = newValue
            case .scaleX: scaleX = newValue
            case .scaleY: scaleY = newValue
            case .opacity: opacity = newValue
            }
        }
    }
}

/// Every part's channel values, in the figure's part order.
public struct Pose: Hashable, Sendable {
    public var parts: [PartPose]

    public init(parts: [PartPose]) {
        self.parts = parts
    }

    /// Partway from this pose to another: 0 is this one, 1 is `other`.
    public func blended(to other: Pose, amount: Double) -> Pose {
        Pose(
            parts: zip(parts, other.parts).map { start, target in
                var mixed = start
                for channel in Channel.allCases {
                    mixed[channel] = start[channel] + (target[channel] - start[channel]) * amount
                }
                return mixed
            })
    }
}

/// Where a part is drawn: its art's transform from canvas to canvas, and its opacity
/// including its parents'.
public struct Placement: Hashable, Sendable {
    public var transform: Transform
    public var opacity: Double

    public init(transform: Transform, opacity: Double) {
        (self.transform, self.opacity) = (transform, opacity)
    }
}
