/// The token APNs gave this app install, hex-encoded the way the API takes it. iOS hands the app
/// bytes; Apple says not to rely on their length, so any length is kept.
public struct DeviceToken: Hashable, Sendable, CustomStringConvertible {
    /// Lowercase hex, two digits a byte.
    public let description: String

    public init(_ bytes: some Sequence<UInt8>) {
        let digits = Array("0123456789abcdef")
        description = String(bytes.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 0x0F)]] })
    }
}

/// Which APNs servers a token belongs to. A token only works on its own servers.
public enum PushEnvironment: String, Hashable, Sendable, CaseIterable {
    /// A build run from Xcode, and the simulator.
    case sandbox
    /// TestFlight and the App Store.
    case production
}

/// This phone, as the API keeps it for pushes.
public struct PushDevice: Hashable, Sendable {
    public let token: DeviceToken
    public let environment: PushEnvironment

    public init(token: DeviceToken, environment: PushEnvironment) {
        self.token = token
        self.environment = environment
    }
}
