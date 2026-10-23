#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Lays out pills left to right, wrapping onto new lines.
public struct FlowRow: Layout {
    public init() {}

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for (index, origin) in rows.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: Double) -> (origins: [CGPoint], width: Double, height: Double) {
        var origins: [CGPoint] = []
        var left = 0.0
        var top = 0.0
        var rowHeight = 0.0
        var widest = 0.0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if left > 0, left + size.width > width {
                left = 0
                top += rowHeight
                rowHeight = 0
            }
            origins.append(CGPoint(x: left, y: top))
            left += size.width + Space.xs
            widest = max(widest, left - Space.xs)
            rowHeight = max(rowHeight, size.height)
        }
        return (origins, widest, top + rowHeight)
    }
}
#endif
