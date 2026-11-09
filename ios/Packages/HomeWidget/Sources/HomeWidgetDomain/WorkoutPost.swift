import CheckInDomain
import Contracts
import Foundation
import HealthDomain

extension WidgetBoard {
    /// The 训练 the capsule's 打卡 posts for Health's workout `healthID`, as 今天's card would
    /// with nothing added: the sport and minutes, the numbers `sharing` keeps, and the map and
    /// chart it keeps at the front of the row, as the compose page starts them (with the zones the
    /// board's workout carries), to my squad on my day. Nil unless the board still offers that workout, so a second tap, or one after the app
    /// posted it, posts nothing.
    public func checkIn(
        posting healthID: String, from home: Home, sharing: HealthSharing, id: CheckInID, at now: Timestamp
    ) -> CheckIn? {
        guard let offered = workout, offered.id.id == healthID,
            let activity = offered.activity,
            let audience = try? Audience([home.squad.id])
        else { return nil }
        let tiles = sharing.keptTiles(of: offered.workout).map(ComposedTile.workout)
        let training = Training(
            activity: activity, minutes: offered.minutes,
            workout: offered.workout.posting(struck: sharing.struck, positions: tiles.workoutTilePositions))
        return CheckIn(
            id: id, member: home.member, day: day, createdAt: now, audience: audience, entry: .trained(training))
    }
}
