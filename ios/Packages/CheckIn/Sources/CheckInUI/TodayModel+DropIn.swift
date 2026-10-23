#if os(iOS)
import AvatarArt
import CheckInDomain
import Contracts
import DesignSystem
import Foundation

extension TodayModel {
    /// The squad dropping onto a newly picked scene, until everyone has settled and the card,
    /// 打卡 and the tab bar are back.
    struct Arrival {
        let drop: DropIn
        let start: Date
        /// The teammates in the order they drop, the back first; I drop after them.
        let order: [MemberID]

        /// Where `member` (nil for me) is in the drop's order.
        func index(of member: MemberID?) -> Int {
            member.flatMap { order.firstIndex(of: $0) } ?? order.count
        }

        func elapsed(at date: Date) -> Double { date.timeIntervalSince(start) }
    }

    /// Whether the squad is dropping in; the app moves the tab bar with `tabBarOffset(at:)`.
    public var isArriving: Bool { arrival != nil }

    /// How far below its place the tab bar is at `date`, in points, while the squad drops in.
    public func tabBarOffset(at date: Date) -> Double {
        arrival.map { $0.drop.tabBarOffset(at: $0.elapsed(at: date)) } ?? 0
    }

    /// The end of every scene pick: the picked scene has just filled the screen, and the squad
    /// drops onto it one after another, me last, then the card, 打卡 and the tab bar come back
    /// (Tracy, 2026-10-23: 「selecting a new scene always do the open and drop」).
    public func dropIn(on scene: SceneTheme) {
        self.scene = scene
        isBurstOpen = false
        pats.dismissBubble()
        guard let clip = try? PlaceholderCharacter.drop() else { return }
        let depth = { (mate: SquadCast.Mate) in self.cast.stage.position(of: mate.id, at: 0)?.point.y ?? 0 }
        let mates = cast.mates.sorted { depth($0) < depth($1) }
        // Real time, not the injected clock: the drop plays against the display's frames.
        let start = Date.now
        let drop = DropIn(count: mates.count + 1)
        // Unblended, so nobody slides up out of where they stood; each waits above the screen
        // until their turn.
        for (index, mate) in mates.enumerated() {
            try? mate.player.play(clip, now: start.addingTimeInterval(drop.start(of: index)), blending: false)
        }
        try? player?.play(clip, now: start.addingTimeInterval(drop.start(of: mates.count)), blending: false)
        arrival = Arrival(drop: drop, start: start, order: mates.map(\.id))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(drop.finished))
            if arrival?.start == start { arrival = nil }
        }
    }
}
#endif
