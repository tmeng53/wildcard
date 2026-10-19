import AccountDomain

/// Why a call to our API failed. Each case is something the caller can act on.
public enum APIError: Error, Equatable, Sendable {
    /// No access token: the member is signed out, or the session can't give one right now
    /// (`AccountError` says which). The API refusing a freshly renewed token is `.signedOut`, and
    /// a client made with an `AccountSession` signs it out then.
    case account(AccountError)
    /// The API understood the request and said no. Nothing changed; don't retry it as is.
    case refused(Refusal)
    /// The API or the network can't be reached, or the server failed. Try again later.
    case unavailable
    /// The API answered with something this build can't read: the contract moved.
    case unreadableResponse
}

/// The API's stable problem `reason`s the app acts on.
public enum Refusal: Equatable, Sendable {
    /// The check-in id already holds a different check-in.
    case checkInIDConflict
    /// Today's 请假条 is already posted; one a day.
    case disclaimerAlreadyPosted
    /// The member isn't in a squad the request names.
    case squadNotJoined
    /// Made more than 48 hours ago, ahead of the server's clock, or counted for the wrong day.
    case checkInOutOfTime
    /// A photo is someone else's.
    case photoNotYours
    /// Another check-in already uses one of the photos.
    case photoInUse
    /// A photo the check-in lists was never uploaded.
    case photoNotUploaded
    /// Storage refused the photo itself (its type or size). Any other upload failure is
    /// `.unavailable`: trying again gets a fresh upload URL.
    case photoRejected
    /// A time zone the API doesn't know.
    case timeZoneUnknown
    /// Any other refusal, with its `reason`: a request this build should never send.
    case invalid(reason: String)

    init(reason: String) {
        self =
            switch reason {
            case "CHECK_IN_ID_CONFLICT": .checkInIDConflict
            case "DISCLAIMER_ALREADY_POSTED": .disclaimerAlreadyPosted
            case "SQUAD_NOT_JOINED": .squadNotJoined
            case "CHECK_IN_TOO_OLD", "CHECK_IN_IN_THE_FUTURE", "CHECK_IN_DAY_MISMATCH": .checkInOutOfTime
            case "PHOTO_NOT_YOURS": .photoNotYours
            case "PHOTO_IN_USE": .photoInUse
            case "PHOTO_NOT_UPLOADED": .photoNotUploaded
            case "TIME_ZONE_UNKNOWN": .timeZoneUnknown
            default: .invalid(reason: reason)
            }
    }
}
