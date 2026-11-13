import SwiftUI

/// Vertical rhythm. Every height, gap and line height in the app is a multiple of `unit`.
public enum Rhythm {
    /// The baseline unit, in points.
    public static let unit: CGFloat = 4

    /// `n` baseline units, in points.
    public static func u(_ n: CGFloat) -> CGFloat { n * unit }

    /// Rounds `value` down to a multiple of `module` (default: one unit).
    public static func snapDown(_ value: CGFloat, to module: CGFloat = unit) -> CGFloat {
        guard module > 0 else { return value }
        return max(0, (value / module).rounded(.down) * module)
    }

    /// Rounds `value` to the nearest multiple of `module` (default: one unit).
    public static func snap(_ value: CGFloat, to module: CGFloat = unit) -> CGFloat {
        guard module > 0 else { return value }
        return (value / module).rounded() * module
    }

    /// Whether `value` sits on the baseline grid.
    public static func isOnGrid(_ value: CGFloat) -> Bool {
        abs(value - snap(value)) < 0.001
    }
}

/// A type style whose line box is locked to the baseline grid.
public struct TypeSpec: Sendable {
    public let font: Font
    public let lineHeight: CGFloat
    public let tracking: CGFloat

    /// `lineHeight` is snapped to the baseline grid.
    public init(font: Font, lineHeight: CGFloat, tracking: CGFloat = 0) {
        self.font = font
        self.lineHeight = Rhythm.snap(lineHeight)
        self.tracking = tracking
    }
}

public extension View {
    /// Sets a single line of text in `spec`, with a line box of exactly `spec.lineHeight`,
    /// so stacked labels keep the vertical rhythm whatever the font's own metrics are.
    func rhythm(_ spec: TypeSpec) -> some View {
        self.font(spec.font)
            .tracking(spec.tracking)
            .lineLimit(1)
            .frame(height: spec.lineHeight)
    }
}
