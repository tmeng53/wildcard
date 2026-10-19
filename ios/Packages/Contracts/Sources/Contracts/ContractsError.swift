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
    /// A `sport` key that isn't a listed sport or `custom`.
    case unknownSport(String)
    /// A `customSport` name next to a listed sport, or `custom` with no name.
    case strayCustomSport
    /// A timestamp that isn't ISO 8601.
    case invalidTimestamp(String)
}
