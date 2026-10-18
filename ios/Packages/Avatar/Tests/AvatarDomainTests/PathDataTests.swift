import Testing

@testable import AvatarDomain

@Test func readsAbsoluteAndRelativeCommands() throws {
    let path = try PathData.parse("M10 20 l5-5 H30 v10 h-2 Z")
    #expect(
        path == [
            .move(Point(x: 10, y: 20)), .line(Point(x: 15, y: 15)), .line(Point(x: 30, y: 15)),
            .line(Point(x: 30, y: 25)), .line(Point(x: 28, y: 25)), .close,
        ])
}

@Test func extraPairsAfterAMoveAreLines() throws {
    #expect(
        try PathData.parse("m1,1 2,2 3,3")
            == [.move(Point(x: 1, y: 1)), .line(Point(x: 3, y: 3)), .line(Point(x: 6, y: 6))])
}

@Test func numbersRunTogetherAsDesignToolsWriteThem() throws {
    #expect(
        try PathData.parse("M.5.5L-1-2e1")
            == [.move(Point(x: 0.5, y: 0.5)), .line(Point(x: -1, y: -20))])
}

@Test func smoothCurvesReflectThePreviousControlPoint() throws {
    let path = try PathData.parse("M0 0 C0 10 10 10 10 0 S20 -10 20 0 Q25 5 30 0 T40 0")
    #expect(
        path[2] == .curve(end: Point(x: 20, y: 0), control1: Point(x: 10, y: -10), control2: Point(x: 20, y: -10)))
    #expect(path[4] == .quadCurve(end: Point(x: 40, y: 0), control: Point(x: 35, y: -5)))
}

@Test func rejectsWhatThePlayerDoesntDraw() {
    #expect(throws: SVGProblem.unsupportedPathCommand("A")) { try PathData.parse("M0 0 A5 5 0 0 1 10 10") }
    #expect(throws: SVGProblem.pathMustStartWithMove) { try PathData.parse("L1 1") }
    #expect(throws: SVGProblem.invalidNumber("x")) { try PathData.parse("M1 x") }
}
