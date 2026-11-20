#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import MapKit
import SwiftUI

// What 添加位置 and 新建地点 draw places with: the rows, the ticket pins and the selected pin's name.

/// The selected pin's name over it, in graphite like the pin.
struct PinName: View {
    @Environment(\.sceneTheme) private var theme
    let name: String

    var body: some View {
        Text(verbatim: name)
            .typeStyle(TypeRamp.footnoteEmphasis)
            .foregroundStyle(Color(role: .bgCanvas, in: theme))
            .lineLimit(1)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xxs)
            .background(Color(role: .fgDefault, in: theme), in: Capsule())
            .accessibilityHidden(true)
    }
}

/// A row in the list: a place (its kind's icon in a circle, its name and address, and how far it
/// is) or one of Apple Maps' suggestions (a magnifier, its title and its line under it).
struct PlaceRow: View {
    @Environment(\.sceneTheme) private var theme
    let symbol: String
    let name: String
    let detail: String?
    /// Metres from the phone, when known.
    let distance: Double?
    let isSelected: Bool

    private static let disc: Double = 36

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(.system(size: Sizing.smallIcon, weight: .semibold))
                .foregroundStyle(Color(role: isSelected ? .bgCanvas : .fgDefault, in: theme))
                .frame(width: Self.disc, height: Self.disc)
                .background(Color(role: isSelected ? .fgDefault : .bgSubtle, in: theme), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: name)
                    .typeStyle(TypeRamp.pick)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                if let detail {
                    Text(verbatim: detail)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let distance {
                Text(verbatim: Self.distance(distance))
                    .typeStyle(TypeRamp.scoreCaption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    static func distance(_ metres: Double) -> String {
        Measurement(value: metres, unit: UnitLength.meters)
            .formatted(
                .measurement(
                    width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))
                )
                .locale(AppLanguage.current.locale))
    }
}

extension PlaceRow {
    init(found: FoundPlace, isSelected: Bool) {
        self.init(
            symbol: found.place.kind.symbol, name: found.place.name, detail: found.address, distance: found.distance,
            isSelected: isSelected)
    }
}

/// A map pin shaped as the logo's ticket: a stub under a notched tear line, the place's kind's
/// icon above it. Graphite once it is the picked place, else white with a hairline.
struct TicketPin: View {
    @Environment(\.sceneTheme) private var theme
    let symbol: String
    let isPicked: Bool

    private static let size = CGSize(width: 32, height: 46)
    /// The tear line, from the top: the face is a square above it.
    private static let tear: Double = 32

    var body: some View {
        let shape = PinTicket(tear: Self.tear)
        ZStack(alignment: .top) {
            shape.fill(Color(role: isPicked ? .fgDefault : .bgCanvas, in: theme))
            shape.stroke(Color(role: isPicked ? .fgDefault : .borderDefault, in: theme), lineWidth: Sizing.hairline)
            Image(systemName: symbol)
                .font(.system(size: Sizing.smallIcon, weight: .semibold))
                .foregroundStyle(Color(role: isPicked ? .bgCanvas : .fgDefault, in: theme))
                .frame(width: Self.size.width, height: Self.tear)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .shadow(color: Color(role: .fgDefault, in: theme).opacity(0.15), radius: 3, y: 1)
        .accessibilityHidden(true)
    }
}

/// The ticket's outline at pin size: rounded corners and a half-round notch in each side.
private struct PinTicket: Shape {
    let tear: Double
    private let notch: Double = 3.5
    private let corner: Double = 6

    func path(in rect: CGRect) -> Path {
        let ticket = Path(roundedRect: rect, cornerRadius: corner, style: .continuous)
        var notches = Path()
        for side in [rect.minX, rect.maxX] {
            notches.addEllipse(
                in: CGRect(x: side - notch, y: rect.minY + tear - notch, width: notch * 2, height: notch * 2))
        }
        return ticket.subtracting(notches)
    }
}
/// What 新建地点 starts from: the name typed and where the phone is.
struct NewPlace: Hashable, Identifiable {
    let name: String
    /// The kind it starts as.
    let kind: SquadPlaceKind
    let near: CLLocationCoordinate2D?

    var id: String { name }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}
#endif
