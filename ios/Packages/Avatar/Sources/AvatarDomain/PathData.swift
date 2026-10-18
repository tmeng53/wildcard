/// Reads an SVG path's `d` attribute: M L H V C S Q T Z, absolute and relative.
/// Arcs (A) aren't read; design tools write curves when asked to outline or flatten.
enum PathData {
    static func parse(_ text: String) throws(SVGProblem) -> [PathElement] {
        var scanner = NumberScanner(Array(text.unicodeScalars))
        var builder = PathBuilder()
        var command: Character?
        while true {
            scanner.skipSeparators()
            guard let next = scanner.peek() else { break }
            if next.properties.isAlphabetic {
                command = Character(next)
                scanner.advance()
            }
            guard let letter = command, !builder.elements.isEmpty || letter == "M" || letter == "m" else {
                throw .pathMustStartWithMove
            }
            command = try builder.apply(letter, &scanner)
        }
        return builder.elements
    }
}

/// The path so far and the pen's state between commands.
private struct PathBuilder {
    var elements: [PathElement] = []
    private var current = Point(x: 0, y: 0)
    private var subpathStart = Point(x: 0, y: 0)
    /// The last curve's second control point, which S and T reflect.
    private var lastCubicControl: Point?
    private var lastQuadControl: Point?

    /// Adds one command and returns the command that repeats if more numbers follow.
    mutating func apply(_ letter: Character, _ scanner: inout NumberScanner) throws(SVGProblem) -> Character? {
        let relative = letter.isLowercase
        var cubicControl: Point?
        var quadControl: Point?
        var repeated: Character? = letter
        switch letter.uppercased() {
        case "M":
            current = try point(&scanner, relative)
            subpathStart = current
            elements.append(.move(current))
            // Further pairs after a move are lines.
            repeated = relative ? "l" : "L"
        case "L":
            current = try point(&scanner, relative)
            elements.append(.line(current))
        case "H":
            let value = try scanner.number()
            current = Point(x: relative ? current.x + value : value, y: current.y)
            elements.append(.line(current))
        case "V":
            let value = try scanner.number()
            current = Point(x: current.x, y: relative ? current.y + value : value)
            elements.append(.line(current))
        case "C", "S":
            let control1 = try letter.uppercased() == "C" ? point(&scanner, relative) : reflect(lastCubicControl)
            let control2 = try point(&scanner, relative)
            let end = try point(&scanner, relative)
            elements.append(.curve(end: end, control1: control1, control2: control2))
            (current, cubicControl) = (end, control2)
        case "Q", "T":
            let control = try letter.uppercased() == "Q" ? point(&scanner, relative) : reflect(lastQuadControl)
            let end = try point(&scanner, relative)
            elements.append(.quadCurve(end: end, control: control))
            (current, quadControl) = (end, control)
        case "Z":
            elements.append(.close)
            current = subpathStart
            // Z takes no numbers; a number after it is an error, not a repeat.
            repeated = nil
        default:
            throw .unsupportedPathCommand(letter)
        }
        (lastCubicControl, lastQuadControl) = (cubicControl, quadControl)
        return repeated
    }

    private func point(_ scanner: inout NumberScanner, _ relative: Bool) throws(SVGProblem) -> Point {
        let horizontal = try scanner.number()
        let vertical = try scanner.number()
        return relative
            ? Point(x: current.x + horizontal, y: current.y + vertical) : Point(x: horizontal, y: vertical)
    }

    private func reflect(_ control: Point?) -> Point {
        guard let control else { return current }
        return Point(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
    }
}

/// Numbers in SVG attributes: commas or spaces between them, or nothing when a sign or a
/// second decimal point starts the next one ("1-2", "1.5.5").
struct NumberScanner {
    private let scalars: [Unicode.Scalar]
    private var index = 0

    init(_ scalars: [Unicode.Scalar]) {
        self.scalars = scalars
    }

    var isAtEnd: Bool {
        index >= scalars.count
    }

    func peek() -> Unicode.Scalar? {
        index < scalars.count ? scalars[index] : nil
    }

    mutating func advance() {
        index += 1
    }

    mutating func skipSeparators() {
        while let scalar = peek(), scalar == "," || scalar.properties.isWhitespace {
            advance()
        }
    }

    mutating func number() throws(SVGProblem) -> Double {
        skipSeparators()
        let start = index
        skipSign()
        var sawDigit = false
        var sawPoint = false
        while let scalar = peek() {
            if ("0"..."9").contains(scalar) {
                sawDigit = true
            } else if scalar == ".", !sawPoint {
                sawPoint = true
            } else {
                break
            }
            advance()
        }
        if sawDigit, let exponent = peek(), exponent == "e" || exponent == "E" {
            advance()
            skipSign()
            while let scalar = peek(), ("0"..."9").contains(scalar) { advance() }
        }
        var text = ""
        text.unicodeScalars.append(contentsOf: scalars[start..<index])
        guard sawDigit, let value = Double(text) else {
            throw .invalidNumber(text.isEmpty ? String(peek().map(Character.init) ?? " ") : text)
        }
        return value
    }

    private mutating func skipSign() {
        if let sign = peek(), sign == "-" || sign == "+" { advance() }
    }
}
