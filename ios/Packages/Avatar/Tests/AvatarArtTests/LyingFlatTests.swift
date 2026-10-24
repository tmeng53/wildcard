import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

/// 躺平 falls onto its back, a quarter turn and never past it, and stays down to the end with
/// its eyes shut; nothing flips it side-on. Lying down, every look stays on the canvas but for
/// `lyingFlatReach` on either side, its back on the floor.
@Test(arguments: Persona.allCases)
func lyingFlatFallsAndStaysDown(persona: Persona) throws {
    for look in Looks.squad {
        let figure = try PlaceholderCharacter.figure(wearing: look)
        let flat = try figure.bind(PlaceholderCharacter.lyingFlat(persona: persona))
        let (root, torso, eyes) = (try figure.index("root"), try figure.index("torso"), try figure.index("eyes"))
        #expect(!flat.clip.loops)
        for frame in 0...Int(flat.clip.duration * 100) {
            let pose = figure.pose(flat, at: Double(frame) / 100)
            #expect(abs(pose.parts[root].rotation) <= 90 && pose.parts[root].scaleX > 0.85)
            #expect(abs(pose.parts[torso].rotation) <= 15 && pose.parts[torso].scaleX > 0.85)
        }
        let down = PlaceholderCharacter.lyingFlatFrom / persona.accentTempo
        for time in [down, flat.clip.duration] {
            let pose = figure.pose(flat, at: time)
            #expect(pose.parts[root].rotation == -90 && pose.parts[eyes].scaleY < 0.2, "\(persona) at \(time)")
        }
        expectOnCanvas(
            figure, flat, for: flat.clip.duration, "flat \(persona.rawValue)",
            sideways: PlaceholderCharacter.lyingFlatReach, above: 0)
    }
}
