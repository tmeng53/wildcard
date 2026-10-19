import OpenAPIRuntime

extension Configuration {
    /// How a client of the API reads and writes its bodies. Its `date-time` values carry
    /// milliseconds (`2026-10-18T14:03:00.123Z`), which the runtime's default transcoder can't
    /// read, and a retried check-in must send its moment to the same millisecond.
    public static let api = Configuration(dateTranscoder: .iso8601WithFractionalSeconds)
}
