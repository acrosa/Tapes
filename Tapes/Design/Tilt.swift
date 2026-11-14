import CoreMotion
import SwiftUI
import UIKit

/// How the device is being held, as two numbers the faceplate can light itself by.
/// The display's reflection and the shadows under raised parts read it, so the appliance
/// answers to the hand the way a real one answers to the lamp above it.
///
/// Values are smoothed and only published when they move, so a still device costs nothing.
/// With Reduce Motion on, or where there is no motion sensor, both stay at zero.
@MainActor @Observable
final class Tilt {
    /// −1 (left edge down) … 1 (right edge down), in screen coordinates.
    private(set) var x = 0.0
    /// −1 (tipped back, towards flat) … 1 (tipped forward, past upright), in screen coordinates.
    private(set) var y = 0.0

    @ObservationIgnored private let manager = CMMotionManager()

    init() {
        #if DEBUG
        // `-tiltX 0.6 -tiltY 0.3`: a fixed tilt, for looking at the effect in a simulator.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "tiltX") != nil || defaults.object(forKey: "tiltY") != nil {
            x = defaults.double(forKey: "tiltX")
            y = defaults.double(forKey: "tiltY")
        }
        #endif
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive, !UIAccessibility.isReduceMotionEnabled else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let gravity = motion?.gravity else { return }
            let gx = gravity.x, gy = gravity.y
            MainActor.assumeIsolated { self?.update(gx, gy) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    private func update(_ gx: Double, _ gy: Double) {
        // Gravity arrives in the device's own axes. Turn it into the screen's.
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let (right, up): (Double, Double) = switch scene?.interfaceOrientation {
        case .landscapeRight: (-gy, gx)
        case .landscapeLeft: (gy, -gx)
        case .portraitUpsideDown: (-gx, -gy)
        default: (gx, gy)
        }
        // A device held for use leans back about 35°: that is the resting position.
        let targetX = min(max(right * 1.6, -1), 1)
        let targetY = min(max((up + 0.8) * 1.6, -1), 1)
        let nextX = x + (targetX - x) * 0.25
        let nextY = y + (targetY - y) * 0.25
        if abs(nextX - x) > 0.004 { x = nextX }
        if abs(nextY - y) > 0.004 { y = nextY }
    }
}

/// The reflection on the display window: one soft band of light lying across the glass,
/// which slides as the device is tilted. It adds light only, so the text beneath stays legible.
struct GlassGlare: View {
    @Environment(Tilt.self) private var tilt

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(Motion.glare), location: 0.45),
                    .init(color: .white.opacity(Motion.glare * 0.35), location: 0.6),
                    .init(color: .white.opacity(0), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.6, height: geo.size.height * 4)
            .rotationEffect(.degrees(24))
            .position(
                x: geo.size.width * (0.5 + 0.5 * tilt.x),
                y: geo.size.height * (0.5 - 0.4 * tilt.y)
            )
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
