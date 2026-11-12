import Contracts
import Foundation

/// The squad a sign-up joined or made, kept on this phone from 你的小队 until 上场. Joining saves
/// the squad on the server before the last steps, so without it an app closed on 关于你
/// opened home on the next launch, as for a member who had finished signing up.
enum SignUpProgress {
    private struct Saved: Codable {
        var version = 1
        let squad: SquadID
        let madeIt: Bool
        /// A member back in no squad, who only joined or made one; absent in older saves.
        var rejoining: Bool?
    }

    private static let key = "signUpProgress"

    static func save(squad: SquadID, madeIt: Bool, rejoining: Bool) {
        guard let data = try? JSONEncoder().encode(Saved(squad: squad, madeIt: madeIt, rejoining: rejoining))
        else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// The squad of a sign-up that hasn't reached 上场, whether the member made it, and whether they
    /// were back in no squad, only joining or making one.
    static var saved: (squad: SquadID, madeIt: Bool, rejoining: Bool)? {
        guard let data = UserDefaults.standard.data(forKey: key),
            let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.version == 1
        else { return nil }
        return (saved.squad, saved.madeIt, saved.rejoining ?? false)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
