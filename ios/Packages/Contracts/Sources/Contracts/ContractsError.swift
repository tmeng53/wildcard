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
    /// A start time that isn't a time of day (`HH:mm`, 00:00 to 23:59).
    case startTime(String)
    /// More squadmates named as trained with (一起练) than `TrainedWith.limit`, or one twice.
    case trainedWith(Int)
    /// A tagged place whose name is empty, longer than `Place.maxNameLength` or not one line.
    case placeName(Int)
    /// A tagged place outside the world's latitudes and longitudes.
    case placeCoordinate(latitude: Double, longitude: Double)
    /// A caption with a line break; it is one line.
    case multilineCaption
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
    /// A photo size with a side outside `PhotoSize.sideRange`.
    case photoSize(width: Int, height: Int)
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
    /// A birthday before 1900 or after today.
    case birthdayOutOfRange(String)
    /// A comment that is empty or longer than `CommentText.maxLength` characters.
    case commentLength(Int)
    /// Feedback that is empty or longer than `FeedbackText.maxLength` characters.
    case feedbackLength(Int)
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
    /// A 备注 to the captain that is empty or longer than `JoinNote.maxLength` characters.
    case joinNoteLength(Int)
    /// A 备注 with a line break, tab or other control character.
    case multilineJoinNote
    /// A 备注 with nothing visible in it, or with a text-direction control.
    case invisibleJoinNote
    /// A note on a saved place that is empty or longer than `SavedPlaceNote.maxLength` characters.
    case savedPlaceNoteLength(Int)
    /// A note on a saved place with a line break, tab or other control character.
    case multilineSavedPlaceNote
    /// A note on a saved place with nothing visible in it, or with a text-direction control.
    case invisibleSavedPlaceNote
    /// Text that can't be an invite code: not 8 letters from `InviteCode.alphabet`.
    case invalidInviteCode(String)
    /// A timestamp that isn't ISO 8601.
    case invalidTimestamp(String)
    /// A reaction that isn't exactly one emoji.
    case notAnEmoji(String)
    /// A coach id that isn't one: lowercase letters, digits and dashes, starting with a letter.
    case invalidCoachID(String)
    /// A 健康 or 好吃 score outside 1 to 5.
    case mealScore(Int)
}
