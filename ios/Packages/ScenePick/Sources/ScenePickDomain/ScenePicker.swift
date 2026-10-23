import DesignSystem
import Observation

/// When the squad last trained at a scene, as the picker says it above 「就它了」.
public enum LastTrained: Hashable, Sendable {
    /// The squad's scene this week.
    case thisWeek
    /// That many weeks ago, 1 or more.
    case weeksAgo(Int)
    /// Never: the scene is still in its carton.
    case never
}

/// A scene on the picker and when the squad last trained there.
public struct SceneOption: Hashable, Sendable, Identifiable {
    public let scene: SceneTheme
    public let lastTrained: LastTrained

    public init(scene: SceneTheme, lastTrained: LastTrained) {
        self.scene = scene
        self.lastTrained = lastTrained
    }

    public var id: SceneTheme { scene }
    /// A scene the squad has trained at shows as itself; any other comes in a carton.
    public var isOpened: Bool { lastTrained != .never }
}

/// How the picker saves a pick. An adapter talks to the API; previews and UI tests use one in
/// memory.
public protocol ScenePickService: Sendable {
    /// Saves `scene` as the squad's scene for the week being picked.
    func pick(_ scene: SceneTheme) async throws(ScenePickError)
}

/// What can go wrong saving a pick, by what the member can do about it.
public enum ScenePickError: Error, Hashable, Sendable {
    /// No connection, or the server is down: try again.
    case unavailable
    /// Someone already picked this week, or the member may not: the picker closes.
    case notAllowed
}

/// Where the picker is.
public enum ScenePickPhase: Hashable, Sendable {
    case choosing
    /// 「就它了」 was pressed and the pick is being saved.
    case saving
    /// Saved: the reveal plays, and the picker is locked for the week.
    case picked(SceneTheme)
    /// The pick didn't save; the member may try again.
    case failed(ScenePickError)
}

/// Picking next week's scene, once (spec rev 269): tap a tile to choose it, 「就它了」 to pick
/// it, then the reveal. A pick can't be changed.
@MainActor @Observable
public final class ScenePicker {
    /// The scenes in the order the tiles show them.
    public let options: [SceneOption]
    public private(set) var selection: SceneTheme?
    public private(set) var phase: ScenePickPhase = .choosing

    @ObservationIgnored private let service: any ScenePickService

    public init(options: [SceneOption], service: any ScenePickService) {
        self.options = options
        self.service = service
    }

    /// Chooses a tile, while nothing has been picked yet.
    public func select(_ scene: SceneTheme) {
        guard canChoose, options.contains(where: { $0.scene == scene }) else { return }
        selection = scene
    }

    /// When the squad last trained at the chosen scene, for the line above 「就它了」.
    public var selectionLastTrained: LastTrained? {
        options.first { $0.scene == selection }?.lastTrained
    }

    /// Whether 「就它了」 can be pressed.
    public var canConfirm: Bool { canChoose && selection != nil }

    private var canChoose: Bool {
        switch phase {
        case .choosing, .failed(.unavailable): true
        case .saving, .picked, .failed(.notAllowed): false
        }
    }

    /// Saves the chosen scene. On success the reveal to play comes back: with a carton for a
    /// scene the squad has never trained at.
    public func confirm() async -> Unboxing? {
        guard canConfirm, let scene = selection, let option = options.first(where: { $0.scene == scene }) else {
            return nil
        }
        phase = .saving
        do {
            try await service.pick(scene)
        } catch {
            phase = .failed(error)
            return nil
        }
        phase = .picked(scene)
        return Unboxing(boxed: !option.isOpened)
    }
}
