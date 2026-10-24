/// Why a contract value was rejected. Each case is something the caller can act on.
public enum ContractsError: Error, Equatable, Sendable {
    /// A day string that isn't a real `YYYY-MM-DD` date.
    case invalidDay(String)
    /// An id that isn't a UUID.
    case invalidID(String)
    /// A 请假条 that is empty or longer than `Disclaimer.maxLength` characters.
    case disclaimerLength(Int)
    /// A caption that is empty or longer than `Caption.maxLength` characters.
    case captionLength(Int)
    /// Workout minutes outside `WorkoutMinutes.range`.
    case workoutMinutes(Int)
    /// A caption with a line break; it is one line.
    case multilineCaption
    /// A check-in sent to no squads, or more than `Audience.maxSquads`.
    case audienceSize(Int)
    /// A check-in that lists the same squad twice.
    case repeatedSquad
    /// A weekly plan that doesn't have exactly seven days.
    case planLength(Int)
    /// A photo path that is empty.
    case emptyPhotoPath
    /// A photo view URL that isn't a URL.
    case invalidPhotoURL(String)
    /// A check-in with no photos listed, or more than `Photos.maxCount`.
    case photoCount(Int)
    /// A check-in that lists the same photo twice.
    case repeatedPhoto
    /// A 其他 sport name that is empty or longer than `CustomSport.maxLength` characters.
    case customSportLength(Int)
    /// A 其他 sport name with a line break, tab or other control character.
    case multilineCustomSport
    /// A 其他 sport name with nothing visible in it, or with a text-direction control.
    case invisibleCustomSport
    /// A `sport` key that isn't a listed sport or `custom`.
    case unknownSport(String)
    /// A `customSport` name next to a listed sport, or `custom` with no name.
    case strayCustomSport
    /// A player card number outside `JerseyNumber.range`.
    case jerseyNumberOutOfRange(Int)
    /// A catchphrase that is empty or longer than `Catchphrase.maxLength` characters.
    case catchphraseLength(Int)
    /// A catchphrase with a line break; it is one line.
    case multilineCatchphrase
    /// A nickname that is empty or longer than `Nickname.maxLength` characters.
    case nicknameLength(Int)
    /// A nickname with a line break, tab or other control character.
    case multilineNickname
    /// A nickname with nothing visible in it, or with a text-direction control.
    case invisibleNickname
    /// A squad name that is empty or longer than `SquadName.maxLength` characters.
    case squadNameLength(Int)
    /// A squad name with a line break, tab or other control character.
    case multilineSquadName
    /// A squad name with nothing visible in it, or with a text-direction control.
    case invisibleSquadName
    /// Text that can't be an invite code: not 8 letters from `InviteCode.alphabet`.
    case invalidInviteCode(String)
    /// A timestamp that isn't ISO 8601.
    case invalidTimestamp(String)
    /// A reaction that isn't exactly one emoji.
    case notAnEmoji(String)
    /// A scene this build doesn't draw.
    case unknownScene(String)
}
