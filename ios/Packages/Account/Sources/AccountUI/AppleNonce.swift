#if canImport(CryptoKit)
import CryptoKit
import Foundation

/// The nonce of one Sign in with Apple request. Apple signs its SHA-256 into the identity token
/// and the auth provider checks the raw value against it, so a token copied from somewhere else
/// can't be used to sign in.
struct AppleNonce: Sendable, Equatable {
    let raw: String

    /// 32 random bytes from the system's secure generator, as hex.
    static func random() -> AppleNonce {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return AppleNonce(raw: hex(bytes))
    }

    /// What the Apple request carries.
    var hashed: String { Self.hex(SHA256.hash(data: Data(raw.utf8))) }

    private static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
#endif
