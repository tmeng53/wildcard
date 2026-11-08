#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

// The painted parts of a store's front on 商店街, drawn like the App Store screenshots'
// illustrated shops (approved 2026-11-08): the awning, the window's glass, the door, a closed
// store's shutter, the paved street they stand on and the cardboard box a locked piece waits in. The store's colour comes from its badge, so each is passed in; the glass,
// brass and steel are the same for every store. The street (CharacterEditorUI's `StoreStreet`)
// puts the sign, the model in the window and the slogan on them.

/// The awning: stripes of the store's colour and white, each ending in a half circle, with a
/// faint shadow along the top.
public struct ShopAwning: View {
    let color: Color
    /// How many stripes span the awning, alternating colour and white from the leading edge.
    let stripes: Int

    public init(color: Color, stripes: Int = 14) {
        (self.color, self.stripes) = (color, stripes)
    }

    public var body: some View {
        Canvas { context, size in
            let step = size.width / Double(stripes)
            let straight = size.height - step / 2
            for index in 0..<stripes {
                let fill = index.isMultiple(of: 2) ? color : Color(Palette.white)
                let left = step * Double(index)
                // A hair wider than its step, so no seam shows between stripes.
                context.fill(Path(CGRect(x: left, y: 0, width: step + 0.5, height: straight)), with: .color(fill))
                context.fill(
                    Path(ellipseIn: CGRect(x: left, y: straight - step / 2, width: step, height: step)),
                    with: .color(fill))
            }
            context.fill(
                Path(CGRect(x: 0, y: 0, width: size.width, height: 2)), with: .color(Color(Palette.ink).opacity(0.08)))
        }
        .accessibilityHidden(true)
    }

    /// The awning's height for its width: the stripes' straight part and their round ends.
    public static func height(for width: Double, stripes: Int = 14) -> Double {
        22 + width / Double(stripes) / 2
    }
}

/// The window's glass: pale blue with two slanted glints.
public struct ShopGlass: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(Palette.shopGlass)))
            context.rotate(by: .degrees(28))
            let light = Color(Palette.white)
            context.fill(
                Path(CGRect(x: size.width * 0.1, y: -size.height, width: 22, height: size.height * 3)),
                with: .color(light.opacity(0.5)))
            context.fill(
                Path(CGRect(x: size.width * 0.1 + 34, y: -size.height, width: 8, height: size.height * 3)),
                with: .color(light.opacity(0.38)))
        }
        .accessibilityHidden(true)
    }
}

/// The door in the store's darker colour, with a glass pane and a brass knob.
public struct ShopDoor: View {
    let color: Color

    public init(color: Color) {
        self.color = color
    }

    public var body: some View {
        GeometryReader { door in
            let inset = door.size.width * 0.16
            ZStack(alignment: .topLeading) {
                UnevenRoundedRectangle(topLeadingRadius: Radius.thumbnail, topTrailingRadius: Radius.thumbnail)
                    .fill(color)
                RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                    .fill(Color(Palette.shopGlass))
                    .frame(width: door.size.width - inset * 2, height: door.size.height * 0.38)
                    .offset(x: inset, y: inset)
                Circle()
                    .fill(Color(Palette.shopKnob))
                    .frame(width: 10, height: 10)
                    .offset(x: inset, y: door.size.height * 0.62)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A closed store's rolling shutter: steel slats with a white disc and its 「?」 in the middle.
public struct ShopShutter: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(Palette.shutter)))
            var y = 11.0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 2)), with: .color(Color(Palette.shutterSeam)))
                y += 13
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
        .overlay {
            Text(verbatim: "?")
                .typeStyle(TypeRamp.scoreHero)
                .foregroundStyle(Color(Palette.shutterMark))
                .frame(width: 78, height: 78)
                .background(Color(Palette.white), in: Circle())
        }
        .accessibilityHidden(true)
    }
}
/// The street the shops stand on: a kerb along its top and paving stones laid in staggered rows,
/// under a pale sky (`sky`) the page fills with.
public struct ShopPavement: View {
    /// The sky behind the shops.
    public static let sky = Color(Palette.streetSky)
    /// The stones' own colour, for anything that meets the street (the counter's corners).
    public static let stone = Color(Palette.pavement)
    /// The kerb's colour, for a shop's own step down to the street.
    public static let kerb = Color(Palette.kerb)
    /// How tall the kerb along the street's top is.
    public static let kerbHeight: Double = 6
    /// A paving stone's size and the joint between stones.
    private let tile = 48.0
    private let joint = 2.0

    public init() {}

    public var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(Palette.pavement)))
            let seam = GraphicsContext.Shading.color(Color(Palette.paveJoint))
            var row = 0
            var y = Self.kerbHeight + 4 + tile - joint
            // Each row's joints run under the middle of the stones above it.
            while y - tile < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: joint)), with: seam)
                var left = row.isMultiple(of: 2) ? tile - joint : tile / 2 - joint
                while left < size.width {
                    context.fill(
                        Path(CGRect(x: left, y: y - tile + joint, width: joint, height: tile - joint)), with: seam)
                    left += tile
                }
                y += tile
                row += 1
            }
            context.fill(
                Path(CGRect(x: 0, y: 0, width: size.width, height: Self.kerbHeight)), with: .color(Color(Palette.kerb)))
        }
        .accessibilityHidden(true)
    }
}

/// A locked piece's cardboard box on 商店街's rack: the scene pick's kraft (`CartonBox`), small and
/// flat, with its flap's crease, a strip of tape and a big white 「?」.
public struct ShopCarton: View {
    public init() {}

    public var body: some View {
        GeometryReader { box in
            let width = box.size.width
            let height = box.size.height
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 4, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 4
                )
                .fill(Color(Palette.kraft))
                // The box's shaded bottom edge.
                Rectangle()
                    .fill(Color(Palette.kraftShade))
                    .frame(height: height * 0.1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                // The flap's crease and the tape across it.
                Rectangle()
                    .fill(Color(Palette.kraftBandLine))
                    .frame(height: 2)
                    .offset(y: height * 0.18)
                Rectangle()
                    .fill(Color(Palette.kraftTape))
                    .frame(width: width * 0.18, height: height * 0.22)
                Text(verbatim: "?")
                    .typeStyle(TypeRamp.scoreCard)
                    .foregroundStyle(Color(Palette.white))
                    .frame(maxHeight: .infinity)
                    .offset(y: height * 0.1)
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
