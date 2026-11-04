import Contracts

/// Which unlocks the home should tell: the ones this phone hasn't told yet. A phone that never
/// looked tells nothing and takes everything the member already has as told, so updating the app,
/// signing in on a new phone or an admin's gift before then never floods the home.
public enum UnlockNews {
    /// One unlock's key in what a phone has told: a store and a prop may share an id.
    public static func key(_ unlock: Unlock) -> String { "\(unlock.kind.rawValue)/\(unlock.id)" }

    /// The unlocks to tell, the earliest first, and what is told once they are.
    public static func untold(_ unlocks: [Unlock], told: Set<String>?) -> (tell: [Unlock], told: Set<String>) {
        let all = Set(unlocks.map(key))
        guard let told else { return ([], all) }
        let tell = unlocks.filter { !told.contains(key($0)) }.sorted { $0.unlockedAt < $1.unlockedAt }
        return (tell, told.union(all))
    }
}
