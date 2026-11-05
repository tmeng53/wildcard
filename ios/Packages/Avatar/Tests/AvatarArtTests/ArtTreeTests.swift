import Foundation
import Testing

@testable import AvatarArt

// Downloaded art is read the way the screens will before it is used: every file this build
// bundles passes at its own path, and files the screens couldn't read are refused.

private func files(under root: URL, as tree: String) -> [(path: String, data: Data)] {
    let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    return (walk?.allObjects as? [URL] ?? []).compactMap { url in
        guard ["svg", "json", "png"].contains(url.pathExtension), let data = try? Data(contentsOf: url) else {
            return nil
        }
        let relative = url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1)
        return ("\(tree)/\(relative)", data)
    }
}

@Test func everyBundledFileReadsAtItsPath() {
    let bundled =
        files(under: PlaceholderCharacter.folder, as: "avatar")
        + files(under: CoachCharacter.root, as: "coaches")
        + files(under: OpeningArt.root, as: "openings")
    #expect(bundled.count > 500)
    #expect(bundled.filter { !ArtTree.reads($0.data, at: $0.path) }.map(\.path) == [])
}

/// The holiday pieces wait outside the bundle to be uploaded at their paths; each reads there.
@Test func everyHolidayPieceReadsAtThePathItIsUploadedTo() {
    let root = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../HolidayArt/avatar")
    let pieces = files(under: root, as: "avatar")
    #expect(pieces.count == 28)
    #expect(pieces.filter { !ArtTree.reads($0.data, at: $0.path) }.map(\.path) == [])
}

@Test func filesTheScreensCantReadAreRefused() {
    let version = Data(#"{"version":1}"#.utf8)
    #expect(!ArtTree.reads(version, at: "avatar/rig.json"))
    #expect(!ArtTree.reads(version, at: "avatar/editor.json"))
    #expect(!ArtTree.reads(version, at: "avatar/kits.json"))
    #expect(!ArtTree.reads(version, at: "avatar/moves/ski.json"))
    #expect(!ArtTree.reads(version, at: "avatar/art/top/x/tones.json"))
    #expect(!ArtTree.reads(version, at: "avatar/art/top/x/notes.json"))
    #expect(!ArtTree.reads(Data(#"<svg viewBox="0 0 1 1"><circle r="1" fill="red"/></svg>"#.utf8), at: "avatar/a.svg"))
    #expect(!ArtTree.reads(version, at: "openings/trot/timeline.json"))
    #expect(!ArtTree.reads(Data("not a png".utf8), at: "scenes/gym-day@3x.png"))
}
