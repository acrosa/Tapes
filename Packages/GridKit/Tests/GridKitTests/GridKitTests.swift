import Testing
import CoreGraphics
@testable import GridKit

@Test func columnsFillTheContentWidthExactly() {
    for width: CGFloat in [375, 402, 744, 834, 1194, 1366] {
        let grid = ColumnGrid.adaptive(width: width)
        #expect(abs(grid.span(grid.columns) - grid.contentWidth) < 0.001)
        let lastColumnEnd = grid.x(ofColumn: grid.columns - 1) + grid.columnWidth
        #expect(abs(lastColumnEnd - (width - grid.margin)) < 0.001)
    }
}

@Test func columnCountFollowsWidth() {
    #expect(ColumnGrid.adaptive(width: 402).columns == 12)
    #expect(ColumnGrid.adaptive(width: 750, compactHeight: true).columns == 24)
    #expect(ColumnGrid.adaptive(width: 744).columns == 24)
    #expect(ColumnGrid.adaptive(width: 1194).columns == 24)
}

@Test func marginsAndGuttersSitOnTheBaselineGrid() {
    for width: CGFloat in [402, 744, 1194] {
        let grid = ColumnGrid.adaptive(width: width)
        #expect(Rhythm.isOnGrid(grid.margin))
        #expect(Rhythm.isOnGrid(grid.gutter))
    }
}

@Test func zeroWidthDoesNotProduceNegativeColumns() {
    let grid = ColumnGrid.adaptive(width: 0)
    #expect(grid.columnWidth == 0)
    #expect(grid.contentWidth == 0)
}

@Test func snapping() {
    #expect(Rhythm.snapDown(275, to: 8) == 272)
    #expect(Rhythm.snap(18) == 20)
    #expect(Rhythm.u(4) == 16)
    #expect(TypeSpec(font: .body, lineHeight: 18).lineHeight == 20)
}

@Test func unitRowMatchesColumnSpans() {
    let grid = ColumnGrid.adaptive(width: 402)
    let widths = UnitRow(units: [3, 3, 2, 2, 2], spacing: grid.gutter).widths(in: grid.contentWidth)
    #expect(abs(widths[0] - grid.span(3)) < 0.001)
    #expect(abs(widths[2] - grid.span(2)) < 0.001)
    #expect(abs(widths.reduce(0, +) + 4 * grid.gutter - grid.contentWidth) < 0.001)
}

@Test func aModuleIsTheSameSizeUprightAndSideways() {
    // iPhone 18 Pro: 402 wide upright; 750 between the safe areas on its side.
    let upright = ColumnGrid.adaptive(width: 402).span(ColumnGrid.module)
    let sideways = ColumnGrid.adaptive(width: 750, compactHeight: true).span(ColumnGrid.module)
    #expect(abs(upright - sideways) < 2)
}

@Test func rowGridFitsAndSnaps() {
    // 357pt for four bands 16 apart: 77.25 each, snapped down to 72.
    let rows = RowGrid.fitting(height: 357, rows: 4)
    #expect(rows.rowHeight == 72)
    #expect(rows.height == 336)        // 4 × 72 + 3 × 16
    #expect(rows.span(3) == 248)       // 3 × 72 + 2 × 16
    #expect(rows.y(ofRow: 3) == 264)   // 3 × (72 + 16)
    #expect(Rhythm.isOnGrid(rows.y(ofRow: 2)))
    #expect(RowGrid.fitting(height: 200, rows: 4, minimum: 64).rowHeight == 64)
}

@Test func faultsAreFoundOnEachEdge() {
    let grid = ColumnGrid.adaptive(width: 402)
    let good = CGRect(x: grid.x(ofColumn: 3), y: 48, width: grid.span(3), height: 72)
    #expect(grid.fault(of: good).isEmpty)
    #expect(grid.fault(of: good.offsetBy(dx: 5, dy: 0)) == [.leading, .trailing])
    #expect(grid.fault(of: good.offsetBy(dx: 0, dy: 2)) == [.top])
    #expect(grid.fault(of: good.insetBy(dx: 0, dy: 1)) == [.top, .height])
    #expect(grid.fault(of: good.offsetBy(dx: 5, dy: 2), columns: false, rows: false).isEmpty)
    // A third of a point of pixel rounding is not a fault.
    #expect(grid.fault(of: good.offsetBy(dx: 0.33, dy: 0.33)).isEmpty)
}
