import Contracts

/// What a member's day looks like on the home scene. One per member per day: a 练了 wins over
/// a 请假条, and a 请假条 over a planned rest day. Meals don't change where anyone stands.
public enum StageStatus: Hashable, Sendable {
    /// Trained today: does their sport all day long. No activity when it didn't arrive; they
    /// still train, in place.
    case trained(Activity?)
    /// Posted a 请假条: holds it up, awake, until night.
    case disclaimer
    /// Today is a rest day in their weekly plan: sits and cheers.
    case restDay
    /// None of the above: stands in everyday clothes.
    case notYet

    public init(training: TrainingStatus, activity: Activity?, plannedRest: Bool) {
        switch training {
        case .trained:
            self = .trained(activity)
        case .disclaimer:
            self = .disclaimer
        case .notCheckedIn:
            self = plannedRest ? .restDay : .notYet
        }
    }

    /// The ring under the feet and around the head in the card.
    public var ring: StatusRing {
        switch self {
        case .trained, .disclaimer: .checkedIn
        case .restDay: .restDay
        case .notYet: .none
        }
    }
}

/// The status ring, drawn the same way under a character's feet and around their head in the
/// card: thick in the scene's bright colour once checked in, thin and grey on a rest day.
public enum StatusRing: Hashable, Sendable {
    case checkedIn
    case restDay
    case none
}
