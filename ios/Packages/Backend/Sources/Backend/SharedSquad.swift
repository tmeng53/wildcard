import Contracts
import Foundation

/// The squad's characters, kept where the 6pm push view can read them: the push carries the
/// posts and the names, and has no room for looks, so the characters are drawn from here. The app
/// writes it whenever the home loads; it is the member's, so it goes when they sign out.
public struct SharedSquad: Sendable {
    private let file: URL

    /// - Parameter directory: the app group's container (`AppGroup.directory`), or a test's own.
    public init(directory: URL) {
        file = directory.appending(path: "squad.json")
    }

    /// Keeps the looks of everyone in the squad who made their character.
    public func save(_ members: [SquadmateToday]) {
        let saved = Saved(
            version: 1,
            members: members.compactMap { mate in
                mate.character.map {
                    SavedMember(
                        id: mate.member, persona: $0.look.persona, variants: $0.look.variants,
                        colors: $0.look.colors)
                }
            })
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: file, options: .atomic)
        #endif
    }

    /// The looks last kept, by member; empty before the home first loaded.
    public func looks() -> [MemberID: CharacterLook] {
        guard let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Saved.self, from: data),
            saved.version == 1
        else { return [:] }
        return Dictionary(
            saved.members.map {
                ($0.id, CharacterLook(persona: $0.persona, variants: $0.variants, colors: $0.colors))
            }
        ) { first, _ in first }
    }

    public func forget() {
        try? FileManager.default.removeItem(at: file)
    }

}

/// `SharedSquad`'s file: stored JSON, so it carries a `version`.
private struct Saved: Codable {
    let version: Int
    let members: [SavedMember]
}

private struct SavedMember: Codable {
    let id: MemberID
    let persona: String
    let variants: [String: String]
    let colors: [String: String]
}
