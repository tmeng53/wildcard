import Foundation

/// A squad's invite link, `https://wildcardsquad.com/join/K7M2QX9P`: the web page that shows the
/// squad to someone without the app, and, through the site's apple-app-site-association, opens the
/// app on 加入小队 with the code filled in for someone who has it.
public enum InviteLink {
    public static let host = "wildcardsquad.com"

    /// The link for `code`.
    public static func url(for code: InviteCode) -> URL {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = "/join/\(code.text)"
        // Built from a fixed host and a code of 8 letters and digits, so it is always a URL.
        guard let url = parts.url else { preconditionFailure("an invite link is always a URL") }
        return url
    }

    /// The code in `url` when it is an invite link (any case, with or without `www.`), else nil.
    public static func code(in url: URL) -> InviteCode? {
        guard url.scheme?.lowercased() == "https",
            let host = url.host()?.lowercased(), host == Self.host || host == "www.\(Self.host)"
        else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "join" else { return nil }
        return try? InviteCode(parts[1])
    }
}
