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
    /// A photo path that is empty.
    case emptyPhotoPath
}
