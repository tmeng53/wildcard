import AccountDomain
import NotificationsDomain

/// The API's list of the member's phones, as push registration sees it.
public struct APIDeviceRegistry: DeviceRegistry {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func register(_ device: PushDevice) async throws(NotificationsError) {
        do { try await api.register(device) } catch { throw Self.reason(error) }
    }

    public func remove(_ token: DeviceToken) async throws(NotificationsError) {
        do { try await api.removeDevice(token) } catch { throw Self.reason(error) }
    }

    /// Only a session that is over means something to push registration; anything else is
    /// tried again on the next launch.
    private static func reason(_ error: APIError) -> NotificationsError {
        error == .account(.signedOut) ? .signedOut : .unavailable
    }
}
