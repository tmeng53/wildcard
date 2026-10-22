/// What the 请假条 writer came back with.
public enum DisclaimerSuggestions: Hashable, Sendable {
    /// Up to three lines to pick from, each at most `Disclaimer.maxLength`.
    case drafts([String])
    /// The reason touched something the writer won't joke about (self-harm among them); the
    /// author sees a care line instead, and nobody else sees anything.
    case blocked
}

/// The voice the writer takes (spec section 10 A): the 请假条 bubble's style tabs.
public enum DisclaimerStyle: String, CaseIterable, Hashable, Sendable {
    /// 搞笑: deadpan exaggeration, like a news bulletin or match commentary.
    case funny
    /// 发疯: an excited meltdown ramble, never insulting.
    case unhinged
    /// 中二: an anime hero's grand, dramatic voice.
    case heroic
    /// 嘴硬: never admits to slacking off.
    case stubborn
}

/// Turns the member's reason into 请假条 lines in a style. The AI writer is an adapter behind
/// this; a writer that fails returns dice lines instead, so the member never sees an error.
public protocol DisclaimerWriter: Sendable {
    func suggestions(for reason: String, style: DisclaimerStyle) async -> DisclaimerSuggestions
}
