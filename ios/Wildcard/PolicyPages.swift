import Foundation

/// The published privacy policy and terms on wildcardsquad.com, in the member's language:
/// Traditional Chinese, Simplified Chinese, or English for everyone else; and the app's page on
/// the App Store, where members rate it.
enum PolicyPages {
    static var privacyPolicy: URL { page("privacy") }
    static var terms: URL { page("terms") }
    /// The App Store's 撰写评论 sheet for the app (it opens once the app is on the store).
    static let writeReview: URL = {
        guard let url = URL(string: "https://apps.apple.com/app/id6826015677?action=write-review") else {
            fatalError("the App Store address is fixed and well formed")
        }
        return url
    }()

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
