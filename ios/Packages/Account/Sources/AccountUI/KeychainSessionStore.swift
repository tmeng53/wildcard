#if canImport(Security)
import AccountDomain
import Foundation
import Security

/// Keeps the session in the Keychain, as one generic-password item holding `StoredSession`'s
/// JSON. It stays on this device only (never in backups or iCloud Keychain) and is readable
/// after the first unlock, so a background refresh can renew the session. In an access group,
/// the app's extensions share it (the 6pm push reacts as the member).
public struct KeychainSessionStore: SessionStore {
    private let service: String
    private let accessGroup: String?

    /// - Parameters:
    ///   - service: the item's service name; tests pass their own so they never touch the app's.
    ///   - accessGroup: the Keychain access group the app and its extensions share, or nil for
    ///     the app's own.
    public init(service: String = "com.wildcardsquad.wildcard.session", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
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
        switch SecItemUpdate(groupQuery as CFDictionary, update as CFDictionary) {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            // One kept before the group was shared moves into it.
            SecItemDelete(baseQuery as CFDictionary)
            var add = groupQuery
            add[kSecValueData] = data
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            var added = SecItemAdd(add as CFDictionary, nil)
            // A build not signed into the group (a test run) keeps it to itself.
            if added == errSecMissingEntitlement {
                add[kSecAttrAccessGroup] = nil
                added = SecItemAdd(add as CFDictionary, nil)
            }
            guard added == errSecSuccess else { throw .storeFailed }
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

    /// The item in any group this process can read: loading and clearing.
    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "current",
        ]
    }

    /// The item in its group: saving.
    private var groupQuery: [CFString: Any] {
        var query = baseQuery
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
        return query
    }
}
#endif
