/// Why a contract value was rejected. Each case is something the caller can act on.
public enum ContractsError: Error, Equatable, Sendable {
    /// Stored or wire JSON carries a `version` this build doesn't read.
    case unsupportedVersion(Int)
    /// A day string that isn't a real `YYYY-MM-DD` date.
    case invalidDay(String)
    /// Training minutes outside `Training.minutesRange`.
    case minutesOutOfRange(Int)
    /// A 免责声明 that is empty or longer than `Disclaimer.maxLength` characters.
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
    /// A timestamp that isn't ISO 8601.
    case invalidTimestamp(String)
    /// A check-in whose payload keys don't match its `kind`.
    case payloadMismatch(String)
}
