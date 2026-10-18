import Foundation

// swiftlint:disable identifier_name - x, y and a…ty are the names CGPoint and CGAffineTransform use.

/// A point in the character's canvas, in points, with y growing down as on screen.
public struct Point: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// An affine transform with the same layout as `CGAffineTransform`:
/// x' = a·x + c·y + tx, y' = b·x + d·y + ty.
public struct Transform: Hashable, Sendable {
    public var a, b, c, d, tx, ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        (self.a, self.b, self.c, self.d, self.tx, self.ty) = (a, b, c, d, tx, ty)
    }

    public static let identity = Transform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(x: Double, y: Double) -> Transform {
        Transform(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    public static func scale(x: Double, y: Double) -> Transform {
        Transform(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }

    /// Positive degrees turn clockwise on screen.
    public static func rotation(degrees: Double) -> Transform {
        let radians = degrees * .pi / 180
        let (sine, cosine) = (sin(radians), cos(radians))
        return Transform(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)
    }

    /// This transform, then `next`.
    public func then(_ next: Transform) -> Transform {
        Transform(
            a: next.a * a + next.c * b,
            b: next.b * a + next.d * b,
            c: next.a * c + next.c * d,
            d: next.b * c + next.d * d,
            tx: next.a * tx + next.c * ty + next.tx,
            ty: next.b * tx + next.d * ty + next.ty
        )
    }

    public func apply(to point: Point) -> Point {
        Point(x: a * point.x + c * point.y + tx, y: b * point.x + d * point.y + ty)
    }
}

// swiftlint:enable identifier_name
