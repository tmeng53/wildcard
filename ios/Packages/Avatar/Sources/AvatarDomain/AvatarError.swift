/// Why a character's files were rejected. Each case names the file or part to fix.
public enum AvatarError: Error, Equatable, Sendable {
    /// Rig, clip or tones JSON carries a `version` this build doesn't read.
    case unsupportedVersion(Int)
    /// Rig, clip or tones JSON that doesn't match the format; the text says where.
    case malformedJSON(String)
    /// Two parts in a rig share an id.
    case duplicatePart(PartID)
    /// A part names a parent the rig doesn't have.
    case unknownParent(part: PartID, parent: PartID)
    /// Parents that loop back to the part itself.
    case parentCycle(PartID)
    /// A rig or clip file isn't where its loader looked.
    case missingFile(String)
    /// A base art file the rig needs isn't there.
    case missingArt(String)
    /// An outfit picks a variant that has no art for any part.
    case unknownVariant(slot: Slot, variant: String)
    /// An outfit colors a slot it doesn't wear.
    case colorForBareSlot(Slot)
    /// An outfit colors a slot whose variant has no `tones.json`.
    case notRecolorable(slot: Slot, variant: String)
    /// A variant's `tones.json` lists a color its art never paints.
    case unusedTone(slot: Slot, variant: String, color: RGBAColor)
    /// An art file uses SVG this player doesn't draw.
    case invalidSVG(art: String, problem: SVGProblem)
    /// An art file drawn on a different canvas than the rig's.
    case canvasMismatch(art: String)
    /// A clip moves a part the rig doesn't have.
    case unknownPart(clip: String, part: PartID)
    /// A clip whose duration isn't a positive number of seconds.
    case invalidDuration(clip: String)
    /// A track with no keys, keys out of time order, or keys outside the clip.
    case invalidKeyframes(clip: String, part: PartID, channel: Channel)
    /// A key eased by a cubic Bézier whose x values fall outside 0...1.
    case invalidEasing(clip: String, part: PartID, channel: Channel)
    /// Two tracks in one clip move the same channel of the same part.
    case duplicateTrack(clip: String, part: PartID, channel: Channel)
    /// An accent that loops on a one-shot clip, or plays once on a looping one.
    case accentMismatch(clip: String, accent: String)
    /// An accent whose tempo isn't a positive number, or whose strength is negative.
    case invalidAccent(clip: String, accent: String)
    /// An accent track that doesn't start and end at rest (no offset, scale 1).
    case accentNotAtRest(accent: String, part: PartID, channel: Channel)
}

/// What's wrong in an SVG file. Art is exported flat: paths and basic shapes with fills
/// and strokes, no transforms, gradients, filters or text.
public enum SVGProblem: Error, Equatable, Sendable {
    case notXML(String)
    case missingViewBox
    case unsupportedElement(String)
    case unsupportedAttribute(String)
    case unsupportedPathCommand(Character)
    case invalidNumber(String)
    case invalidColor(String)
    case missingAttribute(element: String, attribute: String)
    case pathMustStartWithMove
}
