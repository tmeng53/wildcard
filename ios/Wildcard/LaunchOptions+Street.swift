import AvatarArt
import Contracts
import Foundation

/// The sample member's 商店街 for the UI tests.
extension LaunchOptions {
    /// The sample member's 商店街, as the server works it out for someone who just started, in
    /// November: WARM-UP open with its newer pieces boxed (they take any 练了), DEUCE CLUB's too once
    /// `-uitest-unlocked` has opened it, the other stores still to earn, and POWDER DAY closed.
    static var stock: StreetStock { stock(winter: false) }

    /// `-uitest-winter-on-return`: the street once the app has been in the background, with the
    /// winter switch turned on meanwhile and POWDER DAY open, for the UI test that 商店街 reads it
    /// again on the way back.
    static var stockOnReturn: StreetStock? {
        ProcessInfo.processInfo.arguments.contains("-uitest-winter-on-return") ? stock(winter: true) : nil
    }

    /// The sample street, with POWDER DAY open in `winter`.
    private static func stock(winter: Bool) -> StreetStock {
        let boxed: [String: [(String, Int)]] = [
            "warmup": [
                ("warmup-headphones", 2), ("warmup-stripe", 4), ("warmup-beanie", 6), ("warmup-overalls", 9),
                ("warmup-hightop", 12), ("warmup-raglan", 15), ("warmup-long", 20),
            ],
            "deuce": [
                ("deuce-sweater", 5), ("deuce-dress", 7), ("deuce-socks", 10), ("deuce-cable", 13),
                ("deuce-terry", 16), ("deuce-pants", 20), ("deuce-ball", 30),
            ],
        ]
        let held = Set(unlocked.map(\.id))
        let earned = ["warmup"] + (held.contains("deuce") ? ["deuce"] : []) + (winter ? ["powder"] : [])
        let wear = (try? PlaceholderCharacter.editorChoices().wear.values.joined()).map(Array.init) ?? []
        let pieces = wear.filter { earned.contains($0.store) }.map { piece in
            let toGo = boxed[piece.store]?.first { $0.0 == piece.id }?.1
            let state: StreetStock.State =
                held.contains(piece.id) ? .owned : toGo.map { .locked(toGo: $0) } ?? .available
            return StreetStock.Piece(id: piece.id, store: piece.store, state: state)
        }
        // A store still to earn takes 3 练了 in its sports, none of them made yet.
        let stores = ["warmup", "lap", "nolook", "moss", "halfmoon", "deuce"].map {
            StreetStock.Store(id: $0, isOpen: true, toGo: earned.contains($0) ? nil : 3)
        }
        return StreetStock(stores: stores + [StreetStock.Store(id: "powder", isOpen: winter)], pieces: pieces)
    }
}
