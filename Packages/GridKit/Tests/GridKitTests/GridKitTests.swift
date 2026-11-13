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
    #expect(ColumnGrid.adaptive(width: 744).columns == 8)
    #expect(ColumnGrid.adaptive(width: 1194).columns == 12)
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
