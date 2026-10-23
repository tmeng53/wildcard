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
    /// The check-in is gone, or the member can't see it.
    case checkInNotFound
    /// Today's AI 请假条 drafts are used up.
    case disclaimerDraftsUsedUp
    /// No squad has this invite code.
    case inviteCodeUnknown
    /// The squad has its 8 members.
    case squadFull
    /// The member is in as many squads as they may be.
    case squadLimitReached
    /// The squad id is already another squad's.
    case squadIDConflict
    /// The member hasn't agreed to the AI consent copy, which squads and AI drafts need.
    case aiConsentRequired
    /// The AI consent copy this build shows is older than the API's: the app is out of date.
    case aiConsentCopyOutdated
    /// Only the squad's captain may do this; someone else is captain now.
    case notSquadCaptain
    /// The member named isn't in the squad (any more).
    case squadMemberUnknown
    /// Only last week's crown winners, or the captain when nobody won, pick the week's scene.
    case notScenePicker
    /// Someone already picked this week's scene.
    case sceneAlreadyPicked
    /// The week named isn't the one open for picking: a new week started meanwhile.
    case sceneWeekClosed
    /// Any other refusal, with its `reason`: a request this build should never send.
    case invalid(reason: String)

    init(reason: String) {
        self = Self.byReason[reason] ?? .invalid(reason: reason)
    }

    private static let byReason: [String: Refusal] = [
        "CHECK_IN_ID_CONFLICT": .checkInIDConflict,
        "DISCLAIMER_ALREADY_POSTED": .disclaimerAlreadyPosted,
        "SQUAD_NOT_JOINED": .squadNotJoined,
        "CHECK_IN_TOO_OLD": .checkInOutOfTime,
        "CHECK_IN_IN_THE_FUTURE": .checkInOutOfTime,
        "CHECK_IN_DAY_MISMATCH": .checkInOutOfTime,
        "PHOTO_NOT_YOURS": .photoNotYours,
        "PHOTO_IN_USE": .photoInUse,
        "PHOTO_NOT_UPLOADED": .photoNotUploaded,
        "TIME_ZONE_UNKNOWN": .timeZoneUnknown,
        "CHECK_IN_NOT_FOUND": .checkInNotFound,
        "DISCLAIMER_DRAFTS_USED_UP": .disclaimerDraftsUsedUp,
        "INVITE_CODE_UNKNOWN": .inviteCodeUnknown,
        "SQUAD_FULL": .squadFull,
        "SQUAD_LIMIT_REACHED": .squadLimitReached,
        "SQUAD_ID_CONFLICT": .squadIDConflict,
        "AI_CONSENT_REQUIRED": .aiConsentRequired,
        "AI_CONSENT_COPY_OUTDATED": .aiConsentCopyOutdated,
        "NOT_SQUAD_CAPTAIN": .notSquadCaptain,
        "SQUAD_MEMBER_UNKNOWN": .squadMemberUnknown,
        "NOT_SCENE_PICKER": .notScenePicker,
        "SCENE_ALREADY_PICKED": .sceneAlreadyPicked,
        "SCENE_WEEK_CLOSED": .sceneWeekClosed,
    ]
}
