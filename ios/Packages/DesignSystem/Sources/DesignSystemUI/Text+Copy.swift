#if canImport(SwiftUI)
import SwiftUI

extension CopyLine.StringInterpolation {
    /// A styled `Text` in a line, such as a name in bold: `%@` in its key.
    public mutating func appendInterpolation(_ text: Text) { add("%@", .text(text)) }
}

extension Text {
    /// The app's words for `value`, from `bundle`'s String Catalog or the lines put over it
    /// (`AppCopyLines`), in the language the app speaks, with the catalog's Markdown read:
    /// a key with `\(toGo)` in it fills like `Text("…")`'s. Every line of the app's own goes
    /// through here or `Text(copyKey:bundle:)`, never `Text("…")`, so any of them can change
    /// without a release.
    public init(copy line: CopyLine, bundle: Bundle) {
        guard line.arguments.contains(where: { if case .text = $0 { true } else { false } }) else {
            self.init(AppCopyLines.attributed(line, bundle: bundle))
            return
        }
        // A styled `Text` among the arguments: the line's words with each argument in its place.
        let locale = AppLanguage.current.locale
        let pieces = CopyLine.pieces(of: AppCopyLines.format(forKey: line.key, in: bundle))
        let parts = pieces.compactMap { (piece: CopyLine.Piece) -> Text? in
            switch piece {
            case .words(let words): return Text(verbatim: words)
            case .argument(let index, let conversion):
                guard line.arguments.indices.contains(index) else { return nil }
                if case .text(let argument) = line.arguments[index], let argument = argument as? Text {
                    return argument
                }
                let value = line.arguments[index].value
                return Text(verbatim: String(format: "%\(conversion)", locale: locale, arguments: [value]))
            }
        }
        self = parts.reduce(Text(verbatim: ""), +)
    }

    /// The app's words for a key known only at run time, such as a sport's or a piece's.
    public init(copyKey key: String, bundle: Bundle) {
        self.init(AppCopyLines.attributed(CopyLine(key: key), bundle: bundle))
    }
}
#endif
