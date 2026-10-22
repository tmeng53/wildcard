import AvatarDomain
import Foundation
import Testing

@Test func tracksInterpolateBetweenKeysAndHoldAtTheEnds() {
    let track = track("arm", .rotation, [(0.5, 10), (1.5, 30)])
    #expect(track.value(at: 0) == 10)
    #expect(track.value(at: 1) == 20)
    #expect(track.value(at: 2) == 30)
}

@Test func easingShapesTheMoveIntoAKey() {
    #expect(Easing.linear.progress(0.25) == 0.25)
    #expect(Easing.hold.progress(0.99) == 0)
    #expect(Easing.hold.progress(1) == 1)
    // CSS ease-in-out is symmetric: halfway in time is halfway in value.
    #expect(abs(Easing.easeInOut.progress(0.5) - 0.5) < 1e-6)
    // Values from the same curves solved by bisection, as browsers draw them.
    #expect(abs(Easing.easeIn.progress(0.25) - 0.093465) < 1e-6)
    #expect(abs(Easing.easeOut.progress(0.25) - 0.378138) < 1e-6)
    // backOut overshoots before it settles.
    #expect(abs(Easing.backOut.progress(0.7) - 1.075776) < 1e-6)
    #expect(Easing.backOut.progress(1) == 1)
}

@Test func readsClipJSON() throws {
    let json = Data(
        """
        { "version": 1, "name": "wave", "duration": 1, "loops": false, "tracks": [
          { "part": "arm", "channel": "rotation", "keys": [
            { "t": 0, "v": 0 }, { "t": 0.5, "v": 90, "ease": "easeOut" }, { "t": 1, "v": 0, "ease": [0, 0, 1, 1] } ] } ] }
        """.utf8)
    let clip = try Clip.decode(json)
    #expect(clip.name == "wave")
    #expect(clip.loops == false)
    #expect(clip.tracks[0].keys[1] == Clip.Keyframe(time: 0.5, value: 90, easing: .easeOut))
    #expect(clip.tracks[0].keys[2].easing == .cubicBezier(0, 0, 1, 1))
}

@Test func rejectsClipsThatCantPlay() {
    #expect(throws: AvatarError.unsupportedVersion(2)) {
        try Clip.decode(Data(#"{ "version": 2, "name": "x" }"#.utf8))
    }
    #expect(throws: AvatarError.malformedJSON("missing .duration")) {
        try Clip.decode(Data(#"{ "version": 1, "name": "x", "loops": true, "tracks": [] }"#.utf8))
    }
    #expect(throws: AvatarError.malformedJSON("wave: unknown ease \"bounce\"")) {
        try Clip.decode(
            Data(
                #"""
                { "version": 1, "name": "wave", "duration": 1, "loops": true, "tracks": [
                  { "part": "arm", "channel": "x", "keys": [{ "t": 0, "v": 0, "ease": "bounce" }] } ] }
                """#.utf8))
    }
    #expect(throws: AvatarError.invalidKeyframes(clip: "wave", part: "arm", channel: .x)) {
        try clip("wave", duration: 1, loops: true, [track("arm", .x, [(0.5, 0), (0.2, 1)])])
    }
    #expect(throws: AvatarError.invalidKeyframes(clip: "wave", part: "arm", channel: .x)) {
        try clip("wave", duration: 1, loops: true, [track("arm", .x, [(0, 0), (1.5, 1)])])
    }
    #expect(throws: AvatarError.invalidDuration(clip: "wave")) { try clip("wave", duration: 0, loops: true, []) }
    #expect(throws: AvatarError.invalidEasing(clip: "wave", part: "arm", channel: .x)) {
        try Clip(
            name: "wave", duration: 1, loops: true,
            tracks: [
                .init(part: "arm", channel: .x, keys: [.init(time: 0, value: 0, easing: .cubicBezier(0, 0, -0.5, 1))])
            ])
    }
    #expect(throws: AvatarError.duplicateTrack(clip: "wave", part: "arm", channel: .x)) {
        try clip("wave", duration: 1, loops: true, [track("arm", .x, [(0, 0)]), track("arm", .x, [(0, 1)])])
    }
    #expect(throws: AvatarError.malformedJSON(".tracks[0].keys[0]: unknown key \"easing\"")) {
        try Clip.decode(
            Data(
                #"""
                { "version": 1, "name": "wave", "duration": 1, "loops": true, "tracks": [
                  { "part": "arm", "channel": "x", "keys": [{ "t": 0, "v": 0, "easing": "backOut" }] } ] }
                """#.utf8))
    }
    #expect(throws: AvatarError.invalidEasing(clip: "wave", part: "arm", channel: .x)) {
        try Clip.decode(
            Data(
                #"""
                { "version": 1, "name": "wave", "duration": 1, "loops": true, "tracks": [
                  { "part": "arm", "channel": "x", "keys": [{ "t": 0, "v": 0, "ease": [1.2, 0, 0.5, 1] }] } ] }
                """#.utf8))
    }
}

/// A calm character plays the same move slower: every key keeps its value at a stretched time.
@Test func aClipPlaysAtATempo() throws {
    let wave = try clip("wave", duration: 2, loops: true, [track("arm", .rotation, [(0, 0), (1, 90), (2, 0)])])
    let slow = try wave.atTempo(0.5)
    #expect(slow.duration == 4)
    #expect(slow.tracks[0].value(at: 2) == 90)
    #expect(slow.tracks[0].value(at: 1) == 45)
    #expect(slow.loops)
    #expect(throws: AvatarError.invalidTempo(clip: "wave")) { try wave.atTempo(0) }
    #expect(throws: AvatarError.invalidTempo(clip: "wave")) { try wave.atTempo(.infinity) }
    // Its accents keep in step: a yawn on top plays half as fast too.
    let yawn = try clip("yawn", duration: 3, loops: true, [track("arm", .rotation, [(0, 0), (3, 0)])])
    #expect(try wave.accented(by: yawn, tempo: 0.8).atTempo(0.5).accents.first?.tempo == 0.4)
}
