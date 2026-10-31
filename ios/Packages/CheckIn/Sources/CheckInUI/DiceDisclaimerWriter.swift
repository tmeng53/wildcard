import CheckInDomain
import Contracts
import Foundation
import SportsUI
import Synchronization

/// The dice: ready-made 请假条 lines. They stand in whenever the AI writer is blocked, offline or
/// missing, so the member never sees an error. The lines are the catalog's (`DiceLines`).
public struct DiceDisclaimerWriter: DisclaimerWriter {
    public init() {}

    /// The dice have no styles: every style rolls the same lines.
    public func suggestions(for reason: String, style: DisclaimerStyle) async -> DisclaimerSuggestions {
        .drafts(Self.rollDefault(3))
    }

    /// `count` different lines, in the app's language, from the system's random source.
    static func rollDefault(_ count: Int) -> [String] {
        var generator = SystemRandomNumberGenerator()
        return roll(count, of: DiceLines.shared.lines, using: &generator)
    }

    /// Every line, in the app's language, in a random order.
    static func rollAll() -> [String] { rollDefault(DiceLines.shared.lines.count) }

    /// `count` different lines of `lines`, in the app's language.
    static func roll(
        _ count: Int, of lines: [CatalogNames], using generator: inout some RandomNumberGenerator
    ) -> [String] {
        lines.shuffled(using: &generator).prefix(count).map(\.localized)
    }
}

/// The 请假条 dice lines this app rolls now: the catalog's, which the app sets at launch (the
/// copy it keeps, else the one it ships with) and again whenever a newer catalog arrives. Any
/// thread may read them.
public final class DiceLines: Sendable {
    /// The app's lines.
    public static let shared = DiceLines()

    private let current = Mutex<[CatalogNames]>([])

    init() {}

    public var lines: [CatalogNames] { current.withLock { $0 } }

    public func show(_ lines: [CatalogNames]) { current.withLock { $0 = lines } }
}
