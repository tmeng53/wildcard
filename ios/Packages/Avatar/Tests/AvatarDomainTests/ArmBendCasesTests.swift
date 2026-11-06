import Foundation
import Testing

@testable import AvatarDomain

/// The arm bends the app and the website must draw alike (`Tests/arm-bend-cases.json`): the app
/// writes each case's `bent`, and web/tests/join.spec.js checks the website's player draws the
/// same, so the two players can't drift apart. `ARM_BEND_CASES=write` rewrites them after a
/// deliberate change to `Bend` or `PathData`.
private let casesFile = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../arm-bend-cases.json")
private let artFolder = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "../../Sources/AvatarArt/Placeholder/art")

private func load() throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: casesFile)) as? [String: Any])
}

private func point(_ value: Any?) throws -> Point {
    let pair = try #require(value as? [Double])
    return Point(x: pair[0], y: pair[1])
}

/// A path as the website writes it: absolute M, L, Q, C and Z, two decimals.
private func written(_ path: [PathElement]) -> String {
    func number(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
    func pair(_ point: Point) -> String { "\(number(point.x)) \(number(point.y))" }
    return path.map { element in
        switch element {
        case .move(let point): "M \(pair(point))"
        case .line(let point): "L \(pair(point))"
        case .quadCurve(let end, let control): "Q \(pair(control)) \(pair(end))"
        case .curve(let end, let first, let second): "C \(pair(first)) \(pair(second)) \(pair(end))"
        case .close: "Z"
        }
    }.joined(separator: " ")
}

@Test func theAppDrawsEachArmBendAsTheCasesSay() throws {
    var cases = try load()
    let arm = try #require(cases["arm"] as? [String: Any])
    let bend = { (degrees: Double) throws in
        Bend(
            shoulder: try point(arm["shoulder"]),
            elbow: Rig.Elbow(point: try point(arm["elbow"]), hand: try point(arm["hand"])), degrees: degrees)
    }
    var list = try #require(cases["cases"] as? [[String: Any]])
    for index in list.indices {
        let path = try PathData.parse(try #require(list[index]["d"] as? String))
        let bent = written(try bend(try #require(list[index]["degrees"] as? Double)).apply(to: path))
        if ProcessInfo.processInfo.environment["ARM_BEND_CASES"] == "write" {
            list[index]["bent"] = bent
        } else {
            #expect(list[index]["bent"] as? String == bent, "\(list[index]["about"] ?? index)")
        }
    }
    if ProcessInfo.processInfo.environment["ARM_BEND_CASES"] == "write" {
        cases["cases"] = list
        let data = try JSONSerialization.data(
            withJSONObject: cases, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: casesFile)
    }
}

/// Every command any arm's art is drawn with has a case, so new art written with a command the
/// cases don't cover fails here until one is added.
@Test func theCasesCoverEveryCommandTheArmsAreDrawnWith() throws {
    let drawn = try #require(try load()["cases"] as? [[String: Any]]).map { $0["d"] as? String ?? "" }
    let covered: Set<Character> = Set(drawn.joined().filter { $0.isLetter && $0 != "e" && $0 != "E" })
    let files = try #require(FileManager.default.enumerator(at: artFolder, includingPropertiesForKeys: nil))
    var used: [Character: String] = [:]
    for case let url as URL in files where url.lastPathComponent.hasPrefix("arm") && url.pathExtension == "svg" {
        let svg = try String(contentsOf: url, encoding: .utf8)
        for match in svg.matches(of: #/ d="([^"]*)"/#) {
            for letter in String(match.1).filter(\.isLetter) where letter != "e" && letter != "E" {
                used[letter] = url.path()
            }
        }
    }
    #expect(!used.isEmpty)
    for (letter, path) in used.sorted(by: { $0.key < $1.key }) {
        #expect(covered.contains(letter), "\(path) draws with \(letter), which no case in arm-bend-cases.json has")
    }
}
