import SwiftUI

/// A column grid: `columns` equal columns separated by `gutter`, inset by `margin`.
public struct ColumnGrid: Equatable, Sendable {
    public var columns: Int
    public var margin: CGFloat
    public var gutter: CGFloat
    /// Full container width, margins included.
    public var width: CGFloat

    public init(columns: Int, margin: CGFloat, gutter: CGFloat, width: CGFloat) {
        self.columns = max(1, columns)
        self.margin = margin
        self.gutter = gutter
        self.width = width
    }

    /// Columns in one module of the fine grids. A module (three columns and the two gutters
    /// inside them) is a quarter of a phone's width: the size of one key.
    public static let module = 3

    /// The grid for a container of `width` points. The columns are fine (about 15pt) and parts
    /// are sized in several of them, so a row can be split in halves, thirds, quarters or sixths
    /// and still land on column edges:
    /// 12 columns below 600, 24 from 600. The gutter is 16 everywhere; the margin grows with the width.
    ///
    /// With `compactHeight` (a phone on its side) the margin shrinks to 16, since the safe areas
    /// already inset the sides.
    public static func adaptive(width: CGFloat, compactHeight: Bool = false) -> ColumnGrid {
        if compactHeight {
            return ColumnGrid(columns: 24, margin: 16, gutter: 16, width: width)
        }
        switch width {
        case ..<600: return ColumnGrid(columns: 12, margin: 24, gutter: 16, width: width)
        case ..<900: return ColumnGrid(columns: 24, margin: 32, gutter: 16, width: width)
        default: return ColumnGrid(columns: 24, margin: 40, gutter: 16, width: width)
        }
    }

    /// Width between the margins.
    public var contentWidth: CGFloat { max(0, width - 2 * margin) }

    public var columnWidth: CGFloat {
        max(0, (contentWidth - CGFloat(columns - 1) * gutter) / CGFloat(columns))
    }

    /// Width of `n` adjacent columns, inner gutters included.
    public func span(_ n: Int) -> CGFloat {
        let n = min(max(n, 1), columns)
        return CGFloat(n) * columnWidth + CGFloat(n - 1) * gutter
    }

    /// Leading edge of column `index` (zero-based), measured from the container's leading edge.
    public func x(ofColumn index: Int) -> CGFloat {
        margin + CGFloat(index) * (columnWidth + gutter)
    }
}

public extension EnvironmentValues {
    /// The column grid of the nearest `GridContainer`.
    @Entry var columnGrid = ColumnGrid.adaptive(width: 0)
}

/// Measures its width, derives the adaptive column grid, applies the grid margins to its
/// content and publishes the grid in the environment. Optionally draws the debug overlay.
public struct GridContainer<Content: View>: View {
    private let showsOverlay: Bool
    private let compactHeight: Bool
    private let fixed: ColumnGrid?
    private let content: (ColumnGrid) -> Content
    @State private var width: CGFloat = 0

    public init(showsOverlay: Bool = false, compactHeight: Bool = false, @ViewBuilder content: @escaping (ColumnGrid) -> Content) {
        self.showsOverlay = showsOverlay
        self.compactHeight = compactHeight
        self.fixed = nil
        self.content = content
    }

    /// A container with a grid of its own instead of the adaptive one: a pane that is laid out
    /// apart from its neighbour (one side of a fold). Checked parts inside it are measured
    /// against this grid, and the overlay draws it.
    public init(grid: ColumnGrid, showsOverlay: Bool = false, @ViewBuilder content: @escaping (ColumnGrid) -> Content) {
        self.showsOverlay = showsOverlay
        self.compactHeight = false
        self.fixed = grid
        self.content = content
    }

    public var body: some View {
        let grid = fixed ?? ColumnGrid.adaptive(width: width, compactHeight: compactHeight)
        content(grid)
            .padding(.horizontal, grid.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.columnGrid, grid)
            .environment(\.gridChecks, showsOverlay)
            .coordinateSpace(.named(GridSpace.name))
            .overlay {
                if showsOverlay { GridOverlay(grid: grid) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// Debug overlay: column bands plus baseline rules every unit (stronger every second unit).
public struct GridOverlay: View {
    private let grid: ColumnGrid
    private let color: Color

    public init(grid: ColumnGrid, color: Color = .red) {
        self.grid = grid
        self.color = color
    }

    public var body: some View {
        Canvas { context, size in
            for index in 0..<grid.columns {
                let rect = CGRect(x: grid.x(ofColumn: index), y: 0, width: grid.columnWidth, height: size.height)
                context.fill(Path(rect), with: .color(color.opacity(0.08)))
            }
            var line = 0
            var y: CGFloat = 0
            while y <= size.height {
                var rule = Path()
                rule.move(to: CGPoint(x: 0, y: y))
                rule.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(rule, with: .color(color.opacity(line.isMultiple(of: 2) ? 0.22 : 0.08)), lineWidth: 0.5)
                line += 1
                y += Rhythm.unit
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
