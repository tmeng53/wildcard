import Foundation

/// A squad's language (小队语言): what the AI writes everything the whole squad reads in, its
/// coach's 战术板 and name and the weekly awards, which its captain picks. What one member reads
/// keeps their own app's language.
public struct SquadLanguage: Hashable, Sendable {
    /// The languages the AI writes in, by their tags.
    public enum Language: String, CaseIterable, Hashable, Sendable {
        case simplifiedChinese = "zh-Hans"
        case traditionalChinese = "zh-Hant"
        case english = "en"
    }

    /// The squad's language now: the captain's pick, else the captain's app language.
    public var language: Language
    /// The viewer is the captain, the only one who sets it.
    public let canChange: Bool

    public init(language: Language, canChange: Bool) {
        self.language = language
        self.canChange = canChange
    }
}
