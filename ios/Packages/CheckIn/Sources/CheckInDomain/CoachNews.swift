import Contracts

extension CoachPageCard {
    /// What the coach's row on the squad card says of this card (Tracy, 2026-11-13): the start of
    /// what the coach said, a note's or 战术板 line's words, a challenge's line (else the challenge
    /// itself: 「拉伸 5 分钟」) or a gift's line; nil for a gift the coach gave without one, and for a
    /// coach message, whose line is in three languages for the caller to pick.
    public var newsLine: String? {
        switch kind {
        case .board, .note: return text
        case .challenge:
            guard let challenge else { return text }
            return challenge.line
                ?? [challenge.title, challenge.amount.map(String.init), challenge.unit].compactMap(\.self)
                .joined(separator: " ")
        case .gift: return gift?.line ?? text
        case .message: return nil
        }
    }
}
