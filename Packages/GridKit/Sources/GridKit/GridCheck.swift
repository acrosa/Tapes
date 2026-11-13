import SwiftUI

/// What is wrong with a frame, measured against the grid. Empty means the frame is on the grid.
public struct GridFault: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// The leading edge is not the leading edge of a column.
    public static let leading = GridFault(rawValue: 1)
    /// The trailing edge is not the trailing edge of a column.
    public static let trailing = GridFault(rawValue: 2)
    /// The top edge is not on a baseline.
    public static let top = GridFault(rawValue: 4)
    /// The height is not a whole number of baseline units.
    public static let height = GridFault(rawValue: 8)

    public var description: String {
        var parts: [String] = []
        if contains(.leading) { parts.append("leading edge off the columns") }
        if contains(.trailing) { parts.append("trailing edge off the columns") }
        if contains(.top) { parts.append("top edge off the baseline") }
        if contains(.height) { parts.append("height not a multiple of the unit") }
        return parts.joined(separator: ", ")
    }
}

public extension ColumnGrid {
    /// Checks a frame given in the `GridContainer`'s coordinate space.
    /// `tolerance` allows for the half point lost when frames are rounded to pixels.
    func fault(of frame: CGRect, columns: Bool = true, rows: Bool = true, tolerance: CGFloat = 0.5) -> GridFault {
        var fault: GridFault = []
        if columns, self.columns > 0, columnWidth > 0 {
            let pitch = columnWidth + gutter
            let leading = (frame.minX - margin) / pitch
            if abs(leading - leading.rounded()) * pitch > tolerance { fault.insert(.leading) }
            let trailing = (frame.maxX - margin - columnWidth) / pitch
            if abs(trailing - trailing.rounded()) * pitch > tolerance { fault.insert(.trailing) }
        }
        if rows {
            if abs(frame.minY - Rhythm.snap(frame.minY)) > tolerance { fault.insert(.top) }
            if abs(frame.height - Rhythm.snap(frame.height)) > tolerance { fault.insert(.height) }
        }
        return fault
    }
}

/// The coordinate space every `GridContainer` defines; frames are checked in it.
public enum GridSpace {
    public static let name = "GridKit.container"
}

public extension EnvironmentValues {
    /// True while a `GridContainer` is drawing its overlay. Checked views report their faults then.
    @Entry var gridChecks = false
}

struct GridChecked: ViewModifier {
    let columns: Bool
    let rows: Bool
    @Environment(\.columnGrid) private var grid
    @Environment(\.gridChecks) private var checks
    @State private var frame = CGRect.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GridSpace.name)) } action: { frame = $0 }
            .overlay {
                if checks, frame != .zero {
                    let fault = grid.fault(of: frame, columns: columns, rows: rows)
                    if !fault.isEmpty {
                        Rectangle()
                            .strokeBorder(Color.red, lineWidth: 2)
                            .allowsHitTesting(false)
                            .accessibilityElement()
                            .accessibilityIdentifier("grid-fault")
                            .accessibilityLabel("Off the grid: \(fault.description)")
                    }
                }
            }
    }
}

public extension View {
    /// Declares that this view must sit on the grid: its sides on column edges, its top on a
    /// baseline, its height a whole number of units. While the `GridContainer` shows its overlay,
    /// a view that fails is outlined in red and exposes an accessibility element with the
    /// identifier `grid-fault`, so a UI test can assert there are none.
    ///
    /// Pass `columns: false` for a part that is deliberately not column-wide (a centred dial),
    /// or `rows: false` for one whose height is free.
    func gridChecked(columns: Bool = true, rows: Bool = true) -> some View {
        modifier(GridChecked(columns: columns, rows: rows))
    }
}
