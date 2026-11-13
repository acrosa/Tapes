import SwiftUI

/// A row grid: `rows` bands of equal height separated by `gap`. The vertical twin of `ColumnGrid`.
///
/// Use it whenever a layout has more than one pane side by side. Parts in different panes then
/// start and end on the same lines, instead of each pane stacking its own heights.
public struct RowGrid: Equatable, Sendable {
    public var rows: Int
    public var gap: CGFloat
    public var rowHeight: CGFloat

    public init(rows: Int, gap: CGFloat, rowHeight: CGFloat) {
        self.rows = max(1, rows)
        self.gap = gap
        self.rowHeight = rowHeight
    }

    /// The tallest grid of `rows` bands that fits in `height`, with the band height snapped down
    /// to `module` (two baseline units by default) and never below `minimum`.
    public static func fitting(
        height: CGFloat,
        rows: Int,
        gap: CGFloat = Rhythm.u(4),
        minimum: CGFloat = 0,
        module: CGFloat = Rhythm.u(2)
    ) -> RowGrid {
        let rows = max(1, rows)
        let free = (height - CGFloat(rows - 1) * gap) / CGFloat(rows)
        return RowGrid(rows: rows, gap: gap, rowHeight: max(minimum, Rhythm.snapDown(free, to: module)))
    }

    /// Height of the whole grid.
    public var height: CGFloat { span(rows) }

    /// Height of `n` adjacent bands, inner gaps included.
    public func span(_ n: Int) -> CGFloat {
        let n = min(max(n, 1), rows)
        return CGFloat(n) * rowHeight + CGFloat(n - 1) * gap
    }

    /// Top edge of band `index` (zero-based), measured from the top of the grid.
    public func y(ofRow index: Int) -> CGFloat {
        CGFloat(index) * (rowHeight + gap)
    }
}
