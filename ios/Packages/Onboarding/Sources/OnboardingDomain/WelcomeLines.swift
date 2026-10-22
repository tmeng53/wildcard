import AvatarArt

/// What the squad shouts when a new member lands at 上场: each teammate a line from their
/// persona's pool, the new member one from their own. Every entrance picks afresh, and never the
/// same line twice in one entrance, so squads don't all say the same thing. The 口头禅 is kept for
/// cheering a teammate's 练了, never a welcome.
///
/// The lines themselves are the String Catalog's, keyed `welcome.<persona>.<n>` and
/// `welcome.me.<n>` counting from 1; this says how many each pool has.
public enum WelcomeLines {
    /// Lines in each persona's pool.
    public static let perPersona = 10
    /// Lines in the new member's own pool (报到！, 我来了！...).
    public static let mine = 8

    public enum Speaker: Hashable, Sendable {
        /// The new member, landing.
        case newcomer
        /// A teammate welcoming them.
        case teammate(Persona)
    }

    /// One line for each speaker, in the same order: String Catalog keys. Two teammates with the
    /// same persona say different lines until their pool runs out, then lines come round again.
    public static func pick(for speakers: [Speaker], using generator: inout some RandomNumberGenerator) -> [String] {
        var left: [Speaker: [Int]] = [:]
        return speakers.map { speaker in
            var pool = left[speaker] ?? []
            if pool.isEmpty { pool = Array(1...count(for: speaker)) }
            let line = pool.remove(at: Int.random(in: pool.indices, using: &generator))
            left[speaker] = pool
            return key(speaker, line)
        }
    }

    /// Every key, for checking the String Catalog has them all.
    public static var allKeys: [String] {
        let speakers = [Speaker.newcomer] + Persona.allCases.map(Speaker.teammate)
        return speakers.flatMap { speaker in (1...count(for: speaker)).map { key(speaker, $0) } }
    }

    private static func count(for speaker: Speaker) -> Int {
        speaker == .newcomer ? mine : perPersona
    }

    private static func key(_ speaker: Speaker, _ line: Int) -> String {
        switch speaker {
        case .newcomer: "welcome.me.\(line)"
        case .teammate(let persona): "welcome.\(persona.rawValue).\(line)"
        }
    }
}
