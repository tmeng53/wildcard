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
        guard let found = try find(groupQuery) else {
            guard let legacy = try find(baseQuery) else { return nil }
            if accessGroup != nil { migrate(legacy.data, from: legacy.group) }
            return try StoredSession.decode(legacy.data)
        }
        return try StoredSession.decode(found.data)
    }

    public func save(_ session: Session) async throws(AccountError) {
        let data = try StoredSession.encode(session)
        switch SecItemUpdate(groupQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary) {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            switch add(data, to: groupQuery) {
            case errSecSuccess:
                return
            // Another process added it first.
            case errSecDuplicateItem:
                try replace(data, in: groupQuery)
            case errSecMissingEntitlement:
                try keepOutsideGroup(data)
            default:
                throw .storeFailed
            }
        case errSecMissingEntitlement:
            try keepOutsideGroup(data)
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

    /// The item `query` matches, with the access group it is in; nil when there is none.
    private func find(_ query: [CFString: Any]) throws(AccountError) -> (data: Data, group: String?)? {
        var query = query
        query[kSecReturnData] = true
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess:
            guard let found = item as? [String: Any], let data = found[kSecValueData as String] as? Data else {
                throw .storeCorrupted
            }
            return (data, found[kSecAttrAccessGroup as String] as? String)
        // A build not signed into the group (a test run) finds nothing in it.
        case errSecItemNotFound, errSecMissingEntitlement:
            return nil
        // Not readable before the first unlock after a restart; the item is still there.
        case errSecInteractionNotAllowed:
            throw .storeLocked
        default:
            throw .storeFailed
        }
    }

    private func replace(_ data: Data, in query: [CFString: Any]) throws(AccountError) {
        switch SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) {
        case errSecSuccess: return
        case errSecInteractionNotAllowed: throw .storeLocked
        default: throw .storeFailed
        }
    }

    /// A build not signed into the group (a test run) keeps the session to itself.
    private func keepOutsideGroup(_ data: Data) throws(AccountError) {
        switch add(data, to: baseQuery) {
        case errSecSuccess: return
        case errSecDuplicateItem: try replace(data, in: baseQuery)
        default: throw .storeFailed
        }
    }

    private func add(_ data: Data, to query: [CFString: Any]) -> OSStatus {
        var add = query
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil)
    }

    /// One kept before the group was shared moves into it, so the app's extensions see it at
    /// once: copied first, and the old one removed only once the copy is there.
    private func migrate(_ data: Data, from group: String?) {
        let added = add(data, to: groupQuery)
        guard added == errSecSuccess || added == errSecDuplicateItem, let group else { return }
        var old = baseQuery
        old[kSecAttrAccessGroup] = group
        SecItemDelete(old as CFDictionary)
    }
}
#endif
