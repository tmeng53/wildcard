import Testing

@testable import AvatarDomain

/// A sleeve's outline is its longest solid line: a wider white stripe and a dashed seam that
/// run along the arm aren't it, as on the lap jacket's sleeve.
@Test func theOutlineIsTheLongestSolidLine() throws {
    let art = try Artwork(
        svg: """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 320">
              <path d="M 0 0 L 40 0 L 40 20 Z" fill="#2D5BA0"/>
              <path d="M 2 4 L 30 4" fill="none" stroke="#FFFFFF" stroke-width="3.4"/>
              <path d="M 0 10 L 90 10" fill="none" stroke="#28467E" stroke-width="1.5" stroke-dasharray="2.4 2"/>
              <path d="M 0 0 L 40 0 Q 50 10 40 20" fill="none" stroke="#28467E" stroke-width="2.4"/>
            </svg>
            """)
    let outline = try #require(art.outline?.stroke)
    #expect(outline.width == 2.4)
    #expect(outline.color == RGBAColor(red: 0x28, green: 0x46, blue: 0x7E))
}
