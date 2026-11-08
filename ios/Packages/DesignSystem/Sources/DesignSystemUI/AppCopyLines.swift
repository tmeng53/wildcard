import Contracts
import Foundation
import Synchronization

/// The words the app shows: the String Catalog's, with the lines put over them since this build
/// (`AppCopy`, the catalog's `appCopy` section) standing in front, so a line changes without an
/// app release. Every lookup of the app's own words goes through here (`Text(copy:bundle:)`,
/// `String(copy:bundle:)`, `String(copyKey:bundle:)`; SwiftLint keeps the others out), in the
/// language the app speaks (`AppLanguage`).
///
/// The copy is installed once a launch, before anything shows, so a screen never changes its
/// words while it is up; a newer copy read meanwhile shows from the next launch, as uploaded art
/// does. A line is filled with its arguments by Foundation, as the catalog's are: each language's
/// lines put are written once to a strings file of their own, looked up in place of the catalog's
/// for the keys they hold.
public enum AppCopyLines {
    private struct Installed: Sendable {
        let copy: AppCopy
        /// Each language's strings file of the lines put, as a bundle to look a key up in.
        let bundles: [AppLanguage: URL]
    }

    private static let installed = Mutex(Installed(copy: .none, bundles: [:]))
    /// Each bundle looked a line up in, by its path and language, so a view body that draws a
    /// line finds its bundle without touching the disk again.
    private static let lookups = Mutex([String: Bundle]())

    /// Puts `copy` in front of the catalog's words from now on. `directory` is where its strings
    /// files go: a fresh folder each time, since Foundation keeps a bundle's strings once read.
    public static func install(_ copy: AppCopy, in directory: URL = defaultDirectory()) {
        var bundles: [AppLanguage: URL] = [:]
        for language in AppLanguage.allCases {
            let lines = copy.entries.keys.reduce(into: [String: String]()) { lines, key in
                lines[key] = copy.words(for: key, in: language.rawValue)
            }
            guard !lines.isEmpty,
                let data = try? PropertyListSerialization.data(fromPropertyList: lines, format: .binary, options: 0)
            else { continue }
            let folder = directory.appending(path: "\(language.rawValue).lproj", directoryHint: .isDirectory)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: folder.appending(path: "Localizable.strings"), options: .atomic)
                bundles[language] = folder
            } catch {
                // Not written: this language keeps the catalog's words.
                continue
            }
        }
        installed.withLock { $0 = Installed(copy: copy, bundles: bundles) }
    }

    /// A new folder in the temporary directory, for one install.
    public static func defaultDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "AppCopy/\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// The bundle to look `key` up in, in the language the app speaks: the lines put when one is
    /// put for it, else `bundle`'s catalog in that language.
    static func bundle(forKey key: String, in bundle: Bundle) -> Bundle {
        let language = AppLanguage.current
        let put = installed.withLock { installed -> URL? in
            installed.copy.words(for: key, in: language.rawValue) == nil ? nil : installed.bundles[language]
        }
        if let put, let lines = cached(put.path(percentEncoded: false), make: { Bundle(url: put) }) {
            return lines
        }
        return cached("\(bundle.bundlePath)#\(language.rawValue)") { bundle.inAppLanguage } ?? bundle
    }

    private static func cached(_ path: String, make: () -> Bundle?) -> Bundle? {
        lookups.withLock { lookups in
            if let found = lookups[path] { return found }
            let made = make()
            lookups[path] = made
            return made
        }
    }

    /// `line`'s words, filled with its arguments, in the language the app speaks.
    public static func string(_ line: CopyLine, bundle: Bundle) -> String {
        let format = format(forKey: line.key, in: bundle)
        guard !line.arguments.isEmpty else { return format }
        return String(format: format, locale: AppLanguage.current.locale, arguments: line.arguments.map(\.value))
    }

    /// `line`'s words as `string(_:bundle:)` gives them, as a `Text` reads its own: the
    /// catalog's Markdown (a link) read in a line without arguments, so what people typed into
    /// one never is.
    public static func attributed(_ line: CopyLine, bundle: Bundle) -> AttributedString {
        let words = string(line, bundle: bundle)
        #if canImport(Darwin)
        guard line.arguments.isEmpty,
            let read = try? AttributedString(
                markdown: words, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        else { return AttributedString(words) }
        return read
        #else
        return AttributedString(words)
        #endif
    }

    /// The words for `key`, unfilled: the lines put over it, else `bundle`'s catalog's, else the key.
    static func format(forKey key: String, in bundle: Bundle) -> String {
        let found = Self.bundle(forKey: key, in: bundle)
        // No strings of its own in the language the app speaks, which is the catalog's source
        // language: Xcode writes no table where every line is its key, so the key is the words.
        // Asking the bundle would answer in the process's language, which in an extension is the
        // phone's, not the app's.
        if found === bundle, speaksSourceLanguage(of: bundle) { return key }
        return found.localizedString(forKey: key, value: nil, table: nil)
    }

    /// Whether the app speaks `bundle`'s source language now.
    private static func speaksSourceLanguage(of bundle: Bundle) -> Bool {
        guard let source = bundle.developmentLocalization else { return false }
        return source.caseInsensitiveCompare(AppLanguage.current.rawValue) == .orderedSame
    }
}

extension String {
    /// The app's words for `line`, from `bundle`'s String Catalog or the lines put over it, in
    /// the language the app speaks: `String(copy: "\(name) 的小队", bundle: .module)`.
    public init(copy line: CopyLine, bundle: Bundle) {
        self = AppCopyLines.string(line, bundle: bundle)
    }

    /// The app's words for a key known only at run time (`sport.unknown`, a push's `loc-key`),
    /// unfilled: the lines put over it, else `bundle`'s catalog's, else the key itself.
    public init(copyKey key: String, bundle: Bundle) {
        self = AppCopyLines.format(forKey: key, in: bundle)
    }
}

/// A line of the app's own, written as a `Text`'s is (`"还有 \(toGo) 次开门"`): its String
/// Catalog key, made the way SwiftUI makes a `LocalizedStringKey`'s (an `Int` as `%lld`, a
/// `Double` as `%lf`, a `String` as `%@`, a `%` in a line with arguments as `%%`), and the
/// arguments to fill it with.
///
/// A `Text` goes in too (a styled name), as `%@`: `Text(copy:bundle:)` puts it in its place, keeping
/// its style; a `String` has no place for one, so `String(copy:bundle:)` leaves it out.
public struct CopyLine: ExpressibleByStringInterpolation {
    /// An argument as the format string takes it.
    public enum Argument {
        case string(String)
        case signed(Int64)
        case unsigned(UInt64)
        case number(Double)
        /// A SwiftUI `Text`, kept as it came.
        case text(Any)

        var value: any CVarArg {
            switch self {
            case .string(let string): NSString(string: string)
            case .signed(let int): int
            case .unsigned(let int): int
            case .number(let double): double
            case .text: NSString(string: "")
            }
        }
    }

    /// A part of a format string: words as they stand, or the argument at `index` (from 0) with
    /// its conversion (`lld`, `@`).
    enum Piece: Equatable {
        case words(String)
        case argument(index: Int, conversion: String)
    }

    /// `format` in its parts, `%%` read as `%`, each argument by its position.
    static func pieces(of format: String) -> [Piece] {
        let specifier = /%(?:(\d+)\$)?([-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?[@dDiuUxXoOfFeEgGcCsSpaA]|%)/
        var pieces: [Piece] = []
        var words = ""
        var next = 0
        var rest = format[...]
        while let match = rest.firstMatch(of: specifier) {
            words += rest[..<match.range.lowerBound]
            rest = rest[match.range.upperBound...]
            let conversion = String(match.output.2)
            if conversion == "%" {
                words += "%"
                continue
            }
            if !words.isEmpty { pieces.append(.words(words)) }
            words = ""
            let index = match.output.1.flatMap { Int($0) }.map { $0 - 1 } ?? next
            next = index + 1
            pieces.append(.argument(index: index, conversion: conversion))
        }
        words += rest
        if !words.isEmpty { pieces.append(.words(words)) }
        return pieces
    }

    public let key: String
    public let arguments: [Argument]

    /// A key known only at run time, with no arguments.
    public init(key: String) {
        (self.key, arguments) = (key, [])
    }

    public init(stringLiteral value: String) {
        self.init(key: value)
    }

    public init(stringInterpolation: StringInterpolation) {
        (key, arguments) =
            stringInterpolation.arguments.isEmpty
            ? (stringInterpolation.literal, [])
            : (stringInterpolation.key, stringInterpolation.arguments)
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        /// The key with `%` escaped, as a line with arguments has it.
        var key = ""
        /// The key as written, as a line without arguments has it.
        var literal = ""
        var arguments: [Argument] = []

        public init(literalCapacity: Int, interpolationCount: Int) {}

        public mutating func appendLiteral(_ literal: String) {
            key += literal.replacingOccurrences(of: "%", with: "%%")
            self.literal += literal
        }

        public mutating func appendInterpolation(_ string: String) { add("%@", .string(string)) }
        public mutating func appendInterpolation(_ int: Int) { add("%lld", .signed(Int64(int))) }
        public mutating func appendInterpolation(_ int: Int64) { add("%lld", .signed(int)) }
        public mutating func appendInterpolation(_ int: Int32) { add("%d", .signed(Int64(int))) }
        public mutating func appendInterpolation(_ int: Int16) { add("%d", .signed(Int64(int))) }
        public mutating func appendInterpolation(_ int: Int8) { add("%d", .signed(Int64(int))) }
        public mutating func appendInterpolation(_ int: UInt) { add("%llu", .unsigned(UInt64(int))) }
        public mutating func appendInterpolation(_ int: UInt64) { add("%llu", .unsigned(int)) }
        public mutating func appendInterpolation(_ int: UInt32) { add("%u", .unsigned(UInt64(int))) }
        public mutating func appendInterpolation(_ int: UInt16) { add("%u", .unsigned(UInt64(int))) }
        public mutating func appendInterpolation(_ int: UInt8) { add("%u", .unsigned(UInt64(int))) }
        public mutating func appendInterpolation(_ double: Double) { add("%lf", .number(double)) }
        public mutating func appendInterpolation(_ float: Float) { add("%f", .number(Double(float))) }
        public mutating func appendInterpolation(_ float: CGFloat) { add("%lf", .number(Double(float))) }

        mutating func add(_ specifier: String, _ argument: Argument) {
            key += specifier
            literal += specifier
            arguments.append(argument)
        }
    }
}
