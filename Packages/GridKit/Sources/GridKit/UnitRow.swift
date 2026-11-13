import SwiftUI

/// A row that divides its width into equal units separated by `spacing`, and gives each
/// child a whole number of units (inner gaps included), exactly as columns span a grid.
///
/// `UnitRow(units: [1, 1, 2], spacing: grid.gutter)` on a four-column grid puts the first two
/// children on one column each and the third across two.
public struct UnitRow: Layout {
    private let units: [Int]
    private let spacing: CGFloat

    public init(units: [Int], spacing: CGFloat) {
        self.units = units.map { max(1, $0) }
        self.spacing = spacing
    }

    /// Widths of the children for a row of `width` points.
    public func widths(in width: CGFloat) -> [CGFloat] {
        let total = units.reduce(0, +)
        guard total > 0 else { return [] }
        let unit = max(0, (width - CGFloat(total - 1) * spacing) / CGFloat(total))
        return units.map { CGFloat($0) * unit + CGFloat($0 - 1) * spacing }
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let widths = widths(in: width)
        var height: CGFloat = 0
        for (subview, childWidth) in zip(subviews, widths) {
            let size = subview.sizeThatFits(ProposedViewSize(width: childWidth, height: proposal.height))
            height = max(height, size.height)
        }
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, childWidth) in zip(subviews, widths(in: bounds.width)) {
            subview.place(
                at: CGPoint(x: x + childWidth / 2, y: bounds.minY),
                anchor: .top,
                proposal: ProposedViewSize(width: childWidth, height: bounds.height)
            )
            x += childWidth + spacing
        }
    }
}
