import AvatarArt
import Foundation
import Testing

/// Every persona's name and default 口头禅 have English in AvatarUI's String Catalog. SwiftPM
/// doesn't extract string keys, so this reads the source and the catalog as files, on Linux too.
@Test func everyPersonaLineHasEnglish() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/AvatarUI")
    let code = try String(contentsOf: sources.appendingPathComponent("Persona+Copy.swift"), encoding: .utf8)
    let pattern = try NSRegularExpression(pattern: #"Text\("([^"]+)", bundle: \.module\)"#)
    let keys = pattern.matches(in: code, range: NSRange(code.startIndex..., in: code)).compactMap {
        Range($0.range(at: 1), in: code).map { String(code[$0]) }
    }
    // A name and a line for each.
    #expect(keys.count == Persona.allCases.count * 2)
    let catalogURL = sources.appendingPathComponent("Resources/Localizable.xcstrings")
    let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
    let strings = try #require(catalog?["strings"] as? [String: Any])
    let missing = keys.filter { key in
        let english = ((strings[key] as? [String: Any])?["localizations"] as? [String: Any])?["en"] as? [String: Any]
        return ((english?["stringUnit"] as? [String: Any])?["value"] as? String ?? "").isEmpty
    }
    #expect(missing.isEmpty, "not in the String Catalog with English: \(missing)")
}
