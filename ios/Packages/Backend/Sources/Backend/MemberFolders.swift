import Contracts
import Foundation

/// Where the phone keeps what is a member's (the home's copy, the posts still to go out): a
/// folder per member under one root. What was kept for one account is never read back for
/// another, even when deleting it on sign-out raced a load that saved it again.
public struct MemberFolders: Sendable {
    private let root: URL

    /// - Parameter root: the folder that holds every member's, such as one in Application Support.
    public init(root: URL) {
        self.root = root
    }

    /// The member's folder. Whatever else is under the root (another account's folder, or files
    /// an earlier build kept there) is deleted first.
    public func folder(for member: MemberID) -> URL {
        let mine = member.description
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        for name in names where name != mine {
            try? FileManager.default.removeItem(at: root.appending(path: name))
        }
        return root.appending(path: mine, directoryHint: .isDirectory)
    }

    /// Deletes every member's folder, when the member signs out or deletes their account.
    public func forgetAll() {
        try? FileManager.default.removeItem(at: root)
    }
}
