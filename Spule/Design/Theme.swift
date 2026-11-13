import SwiftUI
import UIKit
import CoreText
import GridKit

// The single source of design tokens. Values and rationale: docs/DESIGN.md and docs/MOTION.md.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// One finish of the appliance. The user picks one in the tapes sheet; until they do,
/// the app is Light or Dark with the system.
enum Theme: String, CaseIterable, Identifiable {
    case light, dark, green

    var id: String { rawValue }

    var name: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .green: "Green"
        }
    }

    /// The system appearance that goes with the finish (status bar, sheets, menus).
    var scheme: ColorScheme { self == .light ? .light : .dark }

    /// The stored choice, or the system's light or dark if nothing is stored.
    static func resolve(stored: String, system: ColorScheme) -> Theme {
        Theme(rawValue: stored) ?? (system == .dark ? .dark : .light)
    }

    var colors: ThemeColors {
        switch self {
        case .light: .light
        case .dark: .dark
        case .green: .green
        }
    }
}

struct ThemeColors {
    /// The faceplate.
    let surface: Color
    /// Raised parts: keys, wheels, the platter.
    let key: Color
    /// Sunken parts: wells, grooves, the tape scale, an unlit lamp.
    let recess: Color
    /// The display window.
    let glass: Color
    /// Marks on raised and sunken parts: numerals, glyphs, pointers.
    let ink: Color
    /// Ticks and small print on raised and sunken parts.
    let inkSecondary: Color
    /// Words printed on the faceplate itself that can be pressed.
    let label: Color
    /// Legends printed on the faceplate itself.
    let legend: Color
    let displayInk: Color
    let displayDim: Color
    /// Orange. Reserved for recording and the playhead.
    let signal: Color
    /// Fluorescent green. A lamp that is lit: something is switched on.
    let lamp: Color
    let hairline: Color
    /// Opacity of the shadow under a raised part.
    let lift: Double
    /// Opacity of the highlight along the top edge of a raised part.
    let sheen: Double

    static let light = ThemeColors(
        surface: Color(hex: 0xECEAE4), key: Color(hex: 0xF7F6F2), recess: Color(hex: 0xDDDAD2), glass: Color(hex: 0x171716),
        ink: Color(hex: 0x1A1A19), inkSecondary: Color(hex: 0x6B6963), label: Color(hex: 0x1A1A19), legend: Color(hex: 0x6B6963),
        displayInk: Color(hex: 0xF2F0EA), displayDim: Color(hex: 0x85837D),
        signal: Color(hex: 0xE8451E), lamp: Color(hex: 0x14D94F),
        hairline: Color(hex: 0x1A1A19, opacity: 0.12), lift: 0.22, sheen: 0.9
    )

    static let dark = ThemeColors(
        surface: Color(hex: 0x1C1C1B), key: Color(hex: 0x2B2B29), recess: Color(hex: 0x121211), glass: Color(hex: 0x0B0B0A),
        ink: Color(hex: 0xE9E7E1), inkSecondary: Color(hex: 0x918F89), label: Color(hex: 0xE9E7E1), legend: Color(hex: 0x918F89),
        displayInk: Color(hex: 0xECEAE4), displayDim: Color(hex: 0x7C7A74),
        signal: Color(hex: 0xF05A30), lamp: Color(hex: 0x3DFF7A),
        hairline: Color(hex: 0xFFFFFF, opacity: 0.12), lift: 0.5, sheen: 0.1
    )

    /// After Braun's grey-green portables: a green body, putty keys and scale, an orange signal.
    /// Here the print on the body is light and the print on the keys is dark.
    static let green = ThemeColors(
        surface: Color(hex: 0x5E6B64), key: Color(hex: 0xDCDCCB), recess: Color(hex: 0xC2C4B2), glass: Color(hex: 0x1B211E),
        ink: Color(hex: 0x1E211E), inkSecondary: Color(hex: 0x4E5149), label: Color(hex: 0xF1EFE4), legend: Color(hex: 0xF1EFE4),
        displayInk: Color(hex: 0xECEAE0), displayDim: Color(hex: 0x8B9089),
        signal: Color(hex: 0xF0621F), lamp: Color(hex: 0x1FE05A),
        hairline: Color(hex: 0x1E211E, opacity: 0.16), lift: 0.35, sheen: 0.6
    )
}

/// The colours of the finish in use. `FaceplateView` sets `current` and rebuilds the faceplate
/// when the finish changes, so views simply read `Palette.surface` and so on.
enum Palette {
    nonisolated(unsafe) static var current = ThemeColors.light

    static var surface: Color { current.surface }
    static var key: Color { current.key }
    static var recess: Color { current.recess }
    static var glass: Color { current.glass }
    static var ink: Color { current.ink }
    static var inkSecondary: Color { current.inkSecondary }
    static var label: Color { current.label }
    static var legend: Color { current.legend }
    static var displayInk: Color { current.displayInk }
    static var displayDim: Color { current.displayDim }
    static var signal: Color { current.signal }
    static var lamp: Color { current.lamp }
    static var hairline: Color { current.hairline }
    static var lift: Double { current.lift }
    static var sheen: Double { current.sheen }
    static let highlight = Color.white
    static let shadow = Color.black
}

enum Typo {
    /// Geist Mono (Vercel, SIL Open Font License) is bundled in `Spule/Fonts`.
    /// Call once at launch, before any text is drawn.
    static func registerFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private static func mono(_ weight: String, _ size: CGFloat) -> Font {
        .custom("GeistMono-\(weight)", fixedSize: size)
    }

    /// The type for a role, at the phone's size or the larger one used on iPad.
    static func spec(_ role: TypeRole, large: Bool) -> TypeSpec {
        switch (role, large) {
        case (.counter, false): TypeSpec(font: mono("Light", 48), lineHeight: 56, tracking: -2.5)
        case (.counter, true): TypeSpec(font: mono("Light", 64), lineHeight: 72, tracking: -3.5)
        case (.numeral, false): TypeSpec(font: mono("Medium", 17), lineHeight: 24, tracking: 0)
        case (.numeral, true): TypeSpec(font: mono("Medium", 22), lineHeight: 28, tracking: 0)
        case (.status, false): TypeSpec(font: mono("Medium", 12), lineHeight: 16, tracking: 0.2)
        case (.status, true): TypeSpec(font: mono("Medium", 15), lineHeight: 20, tracking: 0.3)
        case (.caption, false): TypeSpec(font: mono("Regular", 12), lineHeight: 16, tracking: -0.2)
        case (.caption, true): TypeSpec(font: mono("Regular", 15), lineHeight: 20, tracking: -0.3)
        case (.legend, false): TypeSpec(font: mono("Regular", 12), lineHeight: 16, tracking: -0.2)
        case (.legend, true): TypeSpec(font: mono("Regular", 13), lineHeight: 20, tracking: -0.2)
        }
    }

    /// Scale numerals, drawn in Canvas.
    static func scale(large: Bool) -> Font { mono("Regular", large ? 12 : 10) }
}

/// What a piece of faceplate text is for. Its size follows `Metrics`.
enum TypeRole { case counter, numeral, status, caption, legend }

/// The size the faceplate is built at: the phone's, or a larger one for iPad, where the same
/// parts would otherwise look lost. Every value is a multiple of the 4pt unit.
struct Metrics: Equatable {
    var large = false

    var gap: CGFloat { large ? Rhythm.u(6) : Rhythm.u(4) }
    var header: CGFloat { large ? Rhythm.u(10) : Rhythm.u(8) }
    var display: CGFloat { large ? Rhythm.u(38) : Rhythm.u(28) }
    var displayInset: CGFloat { large ? Rhythm.u(6) : Rhythm.u(4) }
    var scale: CGFloat { large ? Rhythm.u(18) : Rhythm.u(14) }
    /// Height of a key face or a wheel.
    var face: CGFloat { large ? Rhythm.u(14) : Rhythm.u(12) }
    var transport: CGFloat { large ? Rhythm.u(22) : Rhythm.u(16) }
    /// Size of a glyph on a key or in the header.
    var glyph: CGFloat { large ? 22 : 16 }
    var meterDot: CGFloat { large ? 6 : 4 }
    /// Line height of a legend, for sums that include one.
    var legendLine: CGFloat { Typo.spec(.legend, large: large).lineHeight }
    /// A face with its legend beneath.
    var labelledFace: CGFloat { face + Rhythm.u(2) + legendLine }
}

extension EnvironmentValues {
    @Entry var metrics = Metrics()
}

private struct FaceType: ViewModifier {
    let role: TypeRole
    @Environment(\.metrics) private var metrics

    func body(content: Content) -> some View {
        content.rhythm(Typo.spec(role, large: metrics.large))
    }
}

extension View {
    /// Sets faceplate text in the type for `role`, at the size the faceplate is built at.
    func faceType(_ role: TypeRole) -> some View { modifier(FaceType(role: role)) }
}

enum Motion {
    /// A key going down and coming back up.
    static let press = Animation.spring(response: 0.18, dampingFraction: 0.62)
    /// A control returning to a rest value (wheel reset, fader release).
    static let settle = Animation.spring(response: 0.36, dampingFraction: 0.82)
    /// A lamp or state fill changing.
    static let lamp = Animation.easeOut(duration: 0.12)
    /// Words changing in the display.
    static let readout = Animation.easeInOut(duration: 0.16)
    /// How long a transient readout stays in the display.
    static let readoutHold: Duration = .milliseconds(1400)
    /// Peak brightness of the reflection on the display glass.
    static let glare = 0.09
    /// How far, in points, a full tilt moves the shadow under a key. The dial's moves further.
    static let shadowDrift = 1.5
}

@MainActor
enum Haptics {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }

    private static let selection = UISelectionFeedbackGenerator()
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)

    private static let light = UIImpactFeedbackGenerator(style: .light)

    /// The finest division of a scale passing under the finger: the lightest tap there is.
    static func fine() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.35)
    }

    /// A whole division of a scale passing under the finger.
    static func division() {
        guard enabled else { return }
        rigid.impactOccurred(intensity: 0.65)
    }

    /// One detent of a continuous control.
    static func tick() {
        guard enabled else { return }
        selection.selectionChanged()
    }

    /// A finger landing on the platter.
    static func touch() {
        guard enabled else { return }
        soft.impactOccurred(intensity: 0.7)
    }

    /// A hard stop: end of tape, end of a range, a refused action.
    static func stop() {
        guard enabled else { return }
        rigid.impactOccurred(intensity: 1)
    }

    /// A value snapping into its rest position.
    static func snap() {
        guard enabled else { return }
        rigid.impactOccurred(intensity: 0.5)
    }
}
