#if os(iOS)
import AvatarArt
import DesignSystem
import DesignSystemUI
import SwiftUI

// The pieces a storefront on 商店街 is drawn from (`StoreStreet`'s `Storefront`).

/// The awning: stripes of white on the store's colour, scalloped along its bottom edge.
struct Awning: View {
    let color: Color
    @Environment(\.sceneTheme) private var theme
    private let scallops = 7

    var body: some View {
        Canvas { context, size in
            let shape = AwningShape(scallops: scallops).path(in: CGRect(origin: .zero, size: size))
            context.fill(shape, with: .color(color))
            context.clip(to: shape)
            let step = size.width / Double(scallops)
            let stripe = step * 0.22
            for index in 0..<scallops {
                let left = step * (Double(index) + 0.5) - stripe / 2
                context.fill(
                    Path(CGRect(x: left, y: 0, width: stripe, height: size.height)),
                    with: .color(Color(role: .bgCanvas, in: theme)))
            }
        }
        .accessibilityHidden(true)
    }
}

struct AwningShape: Shape {
    let scallops: Int

    func path(in rect: CGRect) -> Path {
        let depth = rect.height * 0.3
        let step = rect.width / Double(scallops)
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - depth))
        for index in (0..<scallops).reversed() {
            let start = step * Double(index + 1)
            let end = step * Double(index)
            path.addQuadCurve(
                to: CGPoint(x: end, y: rect.height - depth),
                control: CGPoint(x: (start + end) / 2, y: rect.height + depth))
        }
        path.closeSubpath()
        return path
    }
}

/// Two slanted glints across a pane of glass.
struct Glints: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Canvas { context, size in
            context.rotate(by: .degrees(24))
            let light = Color(role: .bgCanvas, in: theme).opacity(0.55)
            context.fill(
                Path(CGRect(x: size.width * 0.12, y: -size.height, width: 14, height: size.height * 3)),
                with: .color(light))
            context.fill(
                Path(CGRect(x: size.width * 0.12 + 22, y: -size.height, width: 6, height: size.height * 3)),
                with: .color(light))
        }
        .accessibilityHidden(true)
    }
}

/// The glass door: graphite, a darker pane with a faint glint, and its handle.
struct DoorView: View {
    let height: Double
    let width: Double
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: Radius.pick, topTrailingRadius: Radius.pick)
            .fill(Color(role: .bgBrand, in: theme))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                    .fill(Color(role: .fgOnBrand, in: theme).opacity(0.12))
                    .padding([.top, .horizontal], Space.xs)
                    .padding(.bottom, Space.l)
            }
            .overlay(alignment: .trailing) {
                Capsule()
                    .fill(Color(role: .fgOnBrand, in: theme))
                    .frame(width: Space.xxs, height: Space.m)
                    .padding(.trailing, Space.xxs + Space.xxs / 2)
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

/// A closed store's rolling shutter, with a lock and how it unlocks.
struct Shutter: View {
    let store: EditorChoices.Store
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Canvas { context, size in
            var y = 0.0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y + 9, width: size.width, height: 2)),
                    with: .color(Color(role: .borderDefault, in: theme)))
                y += 11
            }
        }
        .background(Color(role: .bgSubtle, in: theme))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: Radius.pick, topTrailingRadius: Radius.pick))
        .overlay {
            VStack(spacing: Space.xs) {
                Image(systemName: "lock")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .frame(width: Space.xl, height: Space.xl)
                    .background(Color(role: .bgCanvas, in: theme), in: Circle())
                    .accessibilityHidden(true)
                StoreCopy.opens(store)
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xxs)
                    .background(Color(role: .bgCanvas, in: theme), in: Capsule())
            }
        }
    }
}
#endif
