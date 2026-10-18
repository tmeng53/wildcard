/// Why a character's files were rejected. Each case names the file or part to fix.
public enum AvatarError: Error, Equatable, Sendable {
    /// Rig or clip JSON carries a `version` this build doesn't read.
    case unsupportedVersion(Int)
    /// Rig or clip JSON that doesn't match the format; the text says where.
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
    /// Two tracks in one clip move the same channel of the same part.
    case duplicateTrack(clip: String, part: PartID, channel: Channel)
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
