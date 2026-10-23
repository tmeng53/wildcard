/// Where deleting the account is: the member reads what goes, confirms with Apple, the app asks
/// the API, and the account is gone or the member can try again.
public enum DeletionPhase: Hashable, Sendable {
    case reading
    case deleting
    case failed(MeError)
    case deleted

    /// Whether the confirm button takes a tap.
    public var canConfirm: Bool {
        switch self {
        case .reading, .failed: true
        case .deleting, .deleted: false
        }
    }

    /// After a try ends with `error`. Closing Apple's sheet isn't a failure: the page goes back to
    /// reading, as if nothing was tapped.
    public static func after(_ error: MeError) -> DeletionPhase {
        error == .confirmationCanceled ? .reading : .failed(error)
    }
}
