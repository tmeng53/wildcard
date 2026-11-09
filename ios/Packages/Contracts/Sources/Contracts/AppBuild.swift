import Foundation
import Synchronization

/// A build of the app as it numbers itself (CFBundleVersion: `190`, `190.1`), compared number by
/// number, so `190.2` comes before `190.10`. The catalog's `appBuild` names the lowest one that may
/// still run (Tracy, 2026-11-09): an older build shows only 有新版本 until it is updated.
public struct AppBuild: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Its numbers, without trailing zeros, so `190.0` is `190`.
    public let parts: [Int]

    /// Nil for anything but one to three whole numbers joined by dots.
    public init?(_ text: String) {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = pieces.compactMap { piece in piece.allSatisfy(\.isASCII) ? Int(piece) : nil }
        guard (1...3).contains(pieces.count), numbers.count == pieces.count, numbers.allSatisfy({ $0 >= 0 })
        else { return nil }
        var trimmed = numbers
        while trimmed.count > 1, trimmed.last == 0 { trimmed.removeLast() }
        parts = trimmed
    }

    public static func < (lhs: AppBuild, rhs: AppBuild) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let (left, right) = (lhs.parts[safe: index], rhs.parts[safe: index])
            if left != right { return left < right }
        }
        return false
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    /// Whether a build numbered `self` may run while the catalog names `minimum`; any build may
    /// while it names none.
    public func mayRun(withMinimum minimum: AppBuild?) -> Bool {
        minimum.map { self >= $0 } ?? true
    }
}

extension [Int] {
    /// A missing part counts as 0.
    fileprivate subscript(safe index: Int) -> Int { indices.contains(index) ? self[index] : 0 }
}

/// The reaction bar's quick emoji as the app last read them from the catalog (its `reactions`),
/// for every bar a member reacts from. Until the catalog is read, the six the app shipped with.
public final class QuickReactions: Sendable {
    /// The app's.
    public static let shared = QuickReactions()

    /// The bar the app shipped with, in the approved order.
    public static let shipped: [Emoji] = ["❤️", "💪", "😂", "🤤", "😮", "😡"].compactMap { try? Emoji($0) }

    private let current = Mutex<[Emoji]>(QuickReactions.shipped)

    public init() {}

    /// Shows `emoji`; an empty list leaves the shipped bar.
    public func show(_ emoji: [Emoji]) { current.withLock { $0 = emoji.isEmpty ? Self.shipped : emoji } }

    public var emoji: [Emoji] { current.withLock { $0 } }
}
