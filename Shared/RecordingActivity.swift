import ActivityKit
import SwiftUI

/// The Live Activity shown while the tape is recording. Compiled into the app, which starts
/// and ends it, and into the widget extension, which draws it.
struct RecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The track being recorded, counted from one.
        var track: Int
        /// The moment the tape counter would have read 0:00. A timer counting up from here
        /// shows the tape's position without the app having to send updates.
        var tapeZero: Date
    }

    var tapeName: String
}

/// The few colours and faces the Live Activity needs. It is always drawn as the display
/// window: dark glass, light print, the orange signal. Values match `ThemeColors.light`.
enum LiveTheme {
    static let glass = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x16 / 255)
    static let ink = Color(red: 0xF2 / 255, green: 0xF0 / 255, blue: 0xEA / 255)
    static let dim = Color(red: 0x8E / 255, green: 0x8C / 255, blue: 0x86 / 255)
    static let signal = Color(red: 0xF0 / 255, green: 0x5A / 255, blue: 0x30 / 255)

    static func mono(_ weight: String, _ size: CGFloat) -> Font {
        .custom("GeistMono-\(weight)", fixedSize: size)
    }
}
