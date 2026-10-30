import CheckInDomain
import Contracts
import DesignSystemUI
import Foundation

/// The dice: ready-made 请假条 lines, from the spec's copy table. They stand in whenever the
/// AI writer is blocked, offline or missing, so the member never sees an error.
public struct DiceDisclaimerWriter: DisclaimerWriter {
    /// String Catalog keys; the Chinese line is the key.
    static let lines = [
        "昨天的腿还没回来", "加班到十点，算脑力训练", "下雨，场地条件不允许", "在 Costco 走了两小时，算有氧",
        "deadline 当前，先活下来", "happy hour 有约，社交也是训练", "身体说不，我尊重它", "今天是战略性休息",
    ]

    public init() {}

    /// The dice have no styles: every style rolls the same lines.
    public func suggestions(for reason: String, style: DisclaimerStyle) async -> DisclaimerSuggestions {
        .drafts(Self.rollDefault(3))
    }

    /// `count` different lines, localized, from the system's random source.
    static func rollDefault(_ count: Int) -> [String] {
        var generator = SystemRandomNumberGenerator()
        return roll(count, using: &generator)
    }

    /// `count` different lines, localized.
    static func roll(_ count: Int, using generator: inout some RandomNumberGenerator) -> [String] {
        lines.shuffled(using: &generator).prefix(count).map {
            Bundle.module.inAppLanguage.localizedString(forKey: $0, value: nil, table: nil)
        }
    }
}
