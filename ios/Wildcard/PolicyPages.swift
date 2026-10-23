import Foundation

/// The published privacy policy and terms on wildcardsquad.com, in the member's language:
/// Traditional Chinese, Simplified Chinese, or English for everyone else.
enum PolicyPages {
    static var privacyPolicy: URL { page("privacy") }
    static var terms: URL { page("terms") }

    private static func page(_ name: String) -> URL {
        guard let url = URL(string: "https://wildcardsquad.com/\(folder)\(name)") else {
            fatalError("the policy page addresses are fixed and well formed")
        }
        return url
    }

    /// `zh-hant/` for Traditional Chinese (zh-Hant, zh-TW, zh-HK), `zh/` for other Chinese, none
    /// for English and everyone else.
    private static var folder: String {
        guard let language = Locale.preferredLanguages.first.map(Locale.Language.init(identifier:)),
            language.languageCode == .chinese
        else { return "" }
        return language.script == .hanTraditional ? "zh-hant/" : "zh/"
    }
}
