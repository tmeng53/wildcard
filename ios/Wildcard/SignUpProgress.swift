import Contracts
import Foundation

/// The squad a sign-up joined or made, kept on this phone from 你的小队 until 上场. Joining saves
/// the squad on the server before the last steps, so without it an app closed on 平时练什么？
/// opened home on the next launch, as for a member who had finished signing up.
enum SignUpProgress {
    private struct Saved: Codable {
        var version = 1
        let squad: SquadID
        let madeIt: Bool
    }

    private static let key = "signUpProgress"

    static func save(squad: SquadID, madeIt: Bool) {
        guard let data = try? JSONEncoder().encode(Saved(squad: squad, madeIt: madeIt)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// The squad of a sign-up that hasn't reached 上场, and whether the member made it.
    static var saved: (squad: SquadID, madeIt: Bool)? {
        guard let data = UserDefaults.standard.data(forKey: key),
            let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.version == 1
        else { return nil }
        return (saved.squad, saved.madeIt)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
