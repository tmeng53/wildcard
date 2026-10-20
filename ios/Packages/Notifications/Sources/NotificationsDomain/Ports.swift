/// Whether the member lets the app show notifications, as iOS says.
public enum PushAuthorization: Hashable, Sendable {
    /// Not asked yet.
    case notDetermined
    /// Allowed, quietly (provisional) included.
    case allowed
    /// Turned off, in the prompt or in Settings. Only Settings can turn it back on.
    case denied
}

/// The phone's side: the permission prompt and APNs registration. `NotificationsUI` has the
/// Apple adapter.
public protocol PushSystem: Sendable {
    func authorization() async -> PushAuthorization
    /// Shows the system prompt; true when the member allows notifications.
    func requestAuthorization() async -> Bool
    /// Asks APNs for this install's token; it comes back through `PushRegistration.received(_:)`.
    func registerForRemoteNotifications() async
}

/// Where the phone is registered: the API, for the signed-in member. `Backend` has the adapter.
public protocol DeviceRegistry: Sendable {
    /// Safe to repeat. A phone someone else signed in on before moves to this member.
    func register(_ device: PushDevice) async throws(NotificationsError)
    /// Safe to repeat, and does nothing for a phone that isn't the member's.
    func remove(_ token: DeviceToken) async throws(NotificationsError)
}
