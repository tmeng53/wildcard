import Foundation

/// An opaque sRGB color, one byte per channel, so every token is an exact, reviewable value.
/// Named apart from QuickDraw's `RGBColor`, which macOS imports with SwiftUI.
public struct SRGBColor: Sendable, Hashable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `#RRGGBB`, uppercase, as designers write it.
    public var hex: String {
        "#" + [red, green, blue].map(Self.twoDigitHex).joined()
    }

    /// WCAG 2.x relative luminance, from 0 (black) to 1 (white).
    public var relativeLuminance: Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            return value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.212_6 * linear(red) + 0.715_2 * linear(green) + 0.072_2 * linear(blue)
    }

    /// WCAG 2.x contrast ratio against another color, from 1 to 21.
    public func contrastRatio(with other: SRGBColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func twoDigitHex(_ value: UInt8) -> String {
        let digits = Array("0123456789ABCDEF")
        return String([digits[Int(value / 16)], digits[Int(value % 16)]])
    }
}
