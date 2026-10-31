/// The number on a member's player card in 我, which they pick: 0 to 99, always shown with two
/// digits (07). Squadmates may share one.
public struct JerseyNumber: Hashable, Sendable {
    /// The API's range; `APIContract`'s tests fail when the two differ.
    public static let range = 0...99

    public let value: Int

    public init(_ value: Int) throws(ContractsError) {
        guard Self.range.contains(value) else { throw .jerseyNumberOutOfRange(value) }
        self.value = value
    }

    /// The number as the card prints it: two digits.
    public var text: String { value < 10 ? "0\(value)" : "\(value)" }
}
