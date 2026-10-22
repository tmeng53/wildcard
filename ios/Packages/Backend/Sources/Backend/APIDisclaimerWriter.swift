import CheckInDomain
import Foundation

/// The AI 请假条 writer behind our API, asked only when the member taps 编几句. Whenever it
/// can't write (offline, out of today's drafts, no model configured, a reason it won't write
/// about), `fallback`, the dice, answers instead, so the member never sees an error.
public struct APIDisclaimerWriter: DisclaimerWriter {
    private let api: WildcardAPI
    private let fallback: any DisclaimerWriter

    public init(api: WildcardAPI, fallback: any DisclaimerWriter) {
        self.api = api
        self.fallback = fallback
    }

    public func suggestions(for reason: String, style: DisclaimerStyle) async -> DisclaimerSuggestions {
        if let written = try? await api.disclaimerDrafts(reason: reason, style: style) { return written }
        return await fallback.suggestions(for: reason, style: style)
    }
}
