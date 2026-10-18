import Testing

@testable import AvatarDomain

@Test func readsShapesWithTheirPaint() throws {
    let art = try Artwork(
        svg: """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 320">
              <title>arm</title>
              <g fill="#2D5BA0">
                <rect x="10" y="20" width="30" height="40" opacity="0.5"/>
                <path d="M0 0 L10 0" fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round"/>
              </g>
              <circle cx="5" cy="6" r="2" style="fill: #22252E; fill-opacity: 0.25"/>
            </svg>
            """)
    #expect(art.width == 240)
    #expect(art.height == 320)
    #expect(art.shapes.count == 3)
    #expect(
        art.shapes[0]
            == ArtShape(
                path: [
                    .move(Point(x: 10, y: 20)), .line(Point(x: 40, y: 20)), .line(Point(x: 40, y: 60)),
                    .line(Point(x: 10, y: 60)), .close,
                ],
                fill: RGBAColor(red: 0x2D, green: 0x5B, blue: 0xA0), stroke: nil, opacity: 0.5))
    #expect(art.shapes[1].fill == nil)
    #expect(art.shapes[1].stroke == Stroke(color: RGBAColor(red: 255, green: 255, blue: 255), width: 4, cap: .round))
    #expect(art.shapes[2].fill == RGBAColor(red: 0x22, green: 0x25, blue: 0x2E, opacity: 0.25))
    #expect(art.shapes[2].opacity == 1)
    // A circle is four quarter curves starting at its rightmost point.
    #expect(art.shapes[2].path.first == .move(Point(x: 7, y: 6)))
    #expect(art.shapes[2].path.count == 6)
}

@Test func roundedRectCornersStayInsideTheRect() throws {
    let art = try Artwork(svg: #"<svg viewBox="0 0 100 100"><rect width="10" height="40" rx="8"/></svg>"#)
    // ry takes the given rx (8); then rx is clamped to half the width (5), ry fits as is.
    #expect(art.shapes[0].path[0] == .move(Point(x: 5, y: 0)))
    #expect(art.shapes[0].path[2].endPoint == Point(x: 10, y: 8))
}

@Test func rejectsSVGThatWouldLookDifferentOnThePhone() {
    #expect(throws: SVGProblem.unsupportedAttribute("transform")) {
        try Artwork(svg: #"<svg viewBox="0 0 10 10"><path d="M0 0" transform="scale(2)"/></svg>"#)
    }
    #expect(throws: SVGProblem.unsupportedElement("linearGradient")) {
        try Artwork(svg: #"<svg viewBox="0 0 10 10"><linearGradient/></svg>"#)
    }
    // A group fades as one piece in SVG, which per-shape opacity can't draw.
    #expect(throws: SVGProblem.unsupportedAttribute("opacity on g")) {
        try Artwork(svg: #"<svg viewBox="0 0 10 10"><g opacity="0.5"><circle r="1"/></g></svg>"#)
    }
    #expect(throws: SVGProblem.invalidColor("red")) {
        try Artwork(svg: #"<svg viewBox="0 0 10 10"><circle r="1" fill="red"/></svg>"#)
    }
    #expect(throws: SVGProblem.missingViewBox) { try Artwork(svg: #"<svg width="10" height="10"/>"#) }
    #expect(throws: SVGProblem.missingAttribute(element: "circle", attribute: "r")) {
        try Artwork(svg: #"<svg viewBox="0 0 10 10"><circle cx="1"/></svg>"#)
    }
}

extension PathElement {
    var endPoint: Point? {
        switch self {
        case .move(let end), .line(let end), .quadCurve(let end, _), .curve(let end, _, _): end
        case .close: nil
        }
    }
}
