#if canImport(Security)
import AccountDomain
import Foundation
import Security

/// Keeps the session in the Keychain, as one generic-password item holding `StoredSession`'s
/// JSON. It stays on this device only (never in backups or iCloud Keychain) and is readable
/// after the first unlock, so a background refresh can renew the session.
public struct KeychainSessionStore: SessionStore {
    private let service: String

    /// - Parameter service: the item's service name; tests pass their own so they never touch
    ///   the app's.
    public init(service: String = "app.wildcard.session") {
        self.service = service
    }

    public func load() async throws(AccountError) -> Session? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess:
            guard let data = item as? Data else { throw .storeCorrupted }
            return try StoredSession.decode(data)
        case errSecItemNotFound:
            return nil
        // Not readable before the first unlock after a restart; the item is still there.
        case errSecInteractionNotAllowed:
            throw .storeLocked
        default:
            throw .storeFailed
        }
    }

    public func save(_ session: Session) async throws(AccountError) {
        let data = try StoredSession.encode(session)
        let update: [CFString: Any] = [kSecValueData: data]
        switch SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary) {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = baseQuery
            add[kSecValueData] = data
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw .storeFailed }
        case errSecInteractionNotAllowed:
            throw .storeLocked
        default:
            throw .storeFailed
        }
    }

    public func clear() async throws(AccountError) {
        switch SecItemDelete(baseQuery as CFDictionary) {
        case errSecSuccess, errSecItemNotFound: return
        default: throw .storeFailed
        }
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "current",
        ]
    }
}
#endif
