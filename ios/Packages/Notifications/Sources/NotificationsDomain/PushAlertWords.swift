/// A push's words as the server sends them: a key in the app's String Catalog (`aps.alert`'s
/// `loc-key`) and the values for its placeholders (`loc-args`). iOS looks the key up in the
/// phone's language, so the app's notification service extension looks it up again in the
/// language the member picked in the app and fills it with these values.
public struct PushAlertWords: Hashable, Sendable {
    /// The String Catalog key.
    public let key: String
    /// The values for the key's placeholders, in order.
    public let args: [String]

    public init(key: String, args: [String] = []) {
        self.key = key
        self.args = args
    }

    /// Reads the words from a payload's `aps`; nil when its alert has no key (a push written in
    /// words, or none at all). Values that aren't text leave the args out.
    public init?(aps: [String: Any]?) {
        guard let alert = aps?["alert"] as? [String: Any], let key = alert["loc-key"] as? String else { return nil }
        self.init(key: key, args: alert["loc-args"] as? [String] ?? [])
    }

    /// The catalog's line for the key, with its placeholders filled as iOS fills them: `%n$@` takes
    /// the n-th value, `%@` the next one in turn, and `%%` is a percent sign. A placeholder with no
    /// value, or of another kind, stays as it is.
    public func fill(_ line: String) -> String {
        var filled = ""
        var next = 0
        var rest = Substring(line)
        while let percent = rest.firstIndex(of: "%") {
            filled += rest[..<percent]
            rest = rest[rest.index(after: percent)...]
            if rest.first == "%" {
                filled += "%"
                rest = rest.dropFirst()
            } else if rest.first == "@" {
                filled += value(at: next) ?? "%@"
                next += 1
                rest = rest.dropFirst()
            } else if let position = Self.position(in: rest) {
                filled += value(at: position.index) ?? "%" + rest[..<position.end]
                rest = rest[position.end...]
            } else {
                filled += "%"
            }
        }
        return filled + rest
    }

    private func value(at index: Int) -> String? {
        args.indices.contains(index) ? args[index] : nil
    }

    /// `n$@` at the start of `text`: the value's index, from 0, and where the placeholder ends.
    private static func position(in text: Substring) -> (index: Int, end: Substring.Index)? {
        let digits = text.prefix(while: \.isASCIIDigit)
        guard let number = Int(digits), number > 0 else { return nil }
        let rest = text[digits.endIndex...]
        guard rest.hasPrefix("$@") else { return nil }
        return (number - 1, rest.index(rest.startIndex, offsetBy: 2))
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
