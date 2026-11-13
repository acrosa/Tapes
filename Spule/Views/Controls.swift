import SwiftUI
import GridKit

/// The look and feel of every pressable key: a raised face that travels down 1.5pt,
/// loses its shadow, and clicks under the finger on the way down (not on release).
struct KeyStyle: ButtonStyle {
    var radius: CGFloat = 8
    var face: Color = Palette.key

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { KeyFace(radius: radius, face: face, down: down) }
            .offset(y: down ? 1.5 : 0)
            .animation(Motion.press, value: down)
            .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.7), trigger: down) { _, isDown in
                isDown && Haptics.enabled
            }
            .contentShape(Rectangle())
    }
}

/// A raised surface. Shared by keys, wheels and fader caps so they read as one material.
struct KeyFace: View {
    var radius: CGFloat = 8
    var face: Color = Palette.key
    var down = false
    @Environment(Tilt.self) private var tilt

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(face)
            .brightness(down ? -0.03 : 0)
            .shadow(
                color: Palette.shadow.opacity(down ? 0.10 : Palette.lift),
                radius: down ? 0.5 : 2.5,
                // The light stays overhead; tilt the device and the shadow leans the other way.
                x: down ? 0 : tilt.x * Motion.shadowDrift,
                y: down ? 0.5 : 2 + tilt.y * Motion.shadowDrift * 0.6
            )
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Palette.highlight.opacity(Palette.sheen), Palette.highlight.opacity(0)],
                        startPoint: .top, endPoint: .center
                    ),
                    lineWidth: 1
                )
            }
            .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 0.5) }
    }
}

/// A small indicator lamp set into a key or the faceplate.
struct Lamp: View {
    var on: Bool
    var color: Color = Palette.lamp

    var body: some View {
        Circle()
            .fill(on ? color : Palette.recess)
            .frame(width: Rhythm.u(2), height: Rhythm.u(2))
            .shadow(color: on ? color.opacity(0.7) : .clear, radius: 4)
            .animation(Motion.lamp, value: on)
    }
}

/// A printed faceplate legend.
struct Legend: View {
    let text: String
    /// Printed on a key rather than on the faceplate.
    var onKey = false

    init(_ text: String, onKey: Bool = false) {
        self.text = text
        self.onKey = onKey
    }

    var body: some View {
        Text(text)
            .faceType(.legend)
            .fixedSize()
            .foregroundStyle(onKey ? Palette.inkSecondary : Palette.legend)
    }
}

/// A key with a lamp on its face and a legend printed beneath it.
struct LampKey: View {
    let legend: String
    var lamp: Bool
    var lampColor: Color = Palette.lamp
    var hint: String = ""
    var faceHeight: CGFloat = Rhythm.u(12)
    let action: () -> Void

    var body: some View {
        VStack(spacing: Rhythm.u(2)) {
            Button(action: action) {
                Lamp(on: lamp, color: lampColor)
            }
            .buttonStyle(KeyStyle())
            .frame(height: faceHeight)
            .accessibilityLabel(legend)
            .accessibilityValue(lamp ? "on" : "off")
            .accessibilityHint(hint)
            Legend(legend)
                .accessibilityHidden(true)
        }
    }
}

/// A thumbwheel: a ridged roller set into a slot as wide as its column, rolled with the thumb
/// along its axis. The ridges travel with the finger; the mark in the gutter beside the roller
/// shows the value. The wheel holds at each detent for a few points of travel.
/// Double-tap returns it to rest, if it has a rest position.
struct Wheel: View {
    let legend: String
    @Binding var value: Double          // 0…1
    var axis: Axis = .vertical
    /// Points of drag for the full range, detents not counted. Longer is finer.
    var travel: CGFloat = 240
    /// The value marked on the faceplate as the rest position.
    var rest: Double?
    /// Values the wheel holds at, in ascending order.
    var detents: [Double] = []
    /// Points of drag the wheel stays in a detent for.
    var detentWidth: CGFloat = 16
    /// Length of the slot along a vertical wheel; thickness of a horizontal one, which is as long as its column.
    var length: CGFloat = Rhythm.u(12)
    var valueText: String
    var onReset: (() -> Void)?

    /// Where the drag started, in drag space (the range plus the width of every detent).
    @State private var start: Double?
    @State private var rolling = false

    private let gutter = Rhythm.u(4)
    private let inset = Rhythm.u(1)
    private let pitch = Rhythm.u(1)

    var body: some View {
        VStack(spacing: Rhythm.u(2)) {
            GeometryReader { geo in
                let along = axis == .vertical ? geo.size.height : geo.size.width
                let across = axis == .vertical ? geo.size.width : geo.size.height
                let roller = size(max(0, along - 2 * inset), max(0, across - gutter - inset))
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.recess)
                    KeyFace(radius: 4, down: start != nil)
                        .overlay { ridges.clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) }
                        .frame(width: roller.width, height: roller.height)
                        .position(point(along / 2, gutter + (across - gutter - inset) / 2, along))
                    if let rest {
                        Capsule()
                            .fill(Palette.inkSecondary)
                            .frame(width: size(1, 12).width, height: size(1, 12).height)
                            .position(point(markPosition(rest, along), gutter / 2, along))
                    }
                    Capsule()
                        .fill(Palette.ink)
                        .frame(width: size(2, 8).width, height: size(2, 8).height)
                        .position(point(markPosition(value, along), gutter / 2, along))
                }
            }
            .frame(height: length)
            .contentShape(Rectangle())
            .gesture(
                // The drag must start at zero distance: with a threshold, the double-tap below never fires.
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let origin = start ?? dragPosition(of: value)
                        start = origin
                        let moved = axis == .vertical ? -drag.translation.height : drag.translation.width
                        guard rolling || abs(moved) >= 2 else { return }
                        rolling = true
                        value = self.value(atDragPosition: origin + moved / travel)
                    }
                    .onEnded { _ in
                        start = nil
                        rolling = false
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    guard let onReset else { return }
                    withAnimation(Motion.settle) { onReset() }
                }
            )
            .animation(Motion.press, value: start != nil)
            .accessibilityElement()
            .accessibilityLabel(legend)
            .accessibilityValue(valueText)
            .accessibilityAdjustableAction { direction in
                value += direction == .increment ? 0.02 : -0.02
            }
            Legend(legend)
                .accessibilityHidden(true)
        }
    }

    // Drag space is the 0…1 range with a flat stretch inserted at every detent, so the wheel
    // rests in a detent without any value becoming unreachable.

    private var detentSpan: Double { detentWidth / travel }

    private func value(atDragPosition position: Double) -> Double {
        var offset = 0.0
        for detent in detents {
            if position < detent + offset { break }
            if position <= detent + offset + detentSpan { return detent }
            offset += detentSpan
        }
        return position - offset
    }

    private func dragPosition(of value: Double) -> Double {
        var position = value
        for detent in detents {
            if value > detent { position += detentSpan } else if value == detent { position += detentSpan / 2 }
        }
        return position
    }

    /// Ridges across the roller. They move one point per point of finger travel.
    private var ridges: some View {
        Canvas { context, size in
            let length = axis == .vertical ? size.height : size.width
            guard length > 0 else { return }
            let phase = (value * travel).truncatingRemainder(dividingBy: pitch)
            var offset = -pitch
            while offset <= length + pitch {
                let position = axis == .vertical ? offset - phase : offset + phase
                let edge = sin(.pi * min(max(position / length, 0), 1))
                var ridge = Path()
                if axis == .vertical {
                    ridge.move(to: CGPoint(x: 0, y: position))
                    ridge.addLine(to: CGPoint(x: size.width, y: position))
                } else {
                    ridge.move(to: CGPoint(x: position, y: 0))
                    ridge.addLine(to: CGPoint(x: position, y: size.height))
                }
                context.stroke(ridge, with: .color(Palette.inkSecondary.opacity(0.5 * edge)), lineWidth: 1)
                offset += pitch
            }
        }
    }

    /// Where a value sits along the slot, measured from its low end.
    private func markPosition(_ value: Double, _ along: CGFloat) -> CGFloat {
        Rhythm.u(2) + CGFloat(min(max(value, 0), 1)) * max(0, along - Rhythm.u(4))
    }

    /// A point given as (distance along the axis from the low end, distance across from the gutter side).
    private func point(_ a: CGFloat, _ c: CGFloat, _ along: CGFloat) -> CGPoint {
        axis == .vertical ? CGPoint(x: c, y: along - a) : CGPoint(x: a, y: c)
    }

    private func size(_ a: CGFloat, _ c: CGFloat) -> CGSize {
        axis == .vertical ? CGSize(width: c, height: a) : CGSize(width: a, height: c)
    }
}

/// A vertical fader with a level meter in its groove.
struct Fader: View {
    @Binding var value: Double          // 0…1
    var level: Float
    var unity: Double
    var label: String

    @State private var start: Double?
    private let cap = CGSize(width: Rhythm.u(12), height: Rhythm.u(8))
    private let groove = Rhythm.u(3)

    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.height - cap.height)
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Palette.recess)
                    .frame(width: groove)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(Palette.ink)
                            .frame(width: groove, height: geo.size.height * CGFloat(meterPosition(level)))
                            .animation(.linear(duration: 0.05), value: level)
                    }
                // 100 %: a line across the strip that the cap's own line meets.
                Rectangle()
                    .fill(Palette.legend)
                    .frame(height: 1)
                    .offset(y: cap.height / 2 + travel * (1 - unity))
                KeyFace(radius: 4, down: start != nil)
                    .overlay { Rectangle().fill(Palette.ink).frame(height: 1.5) }
                    .frame(width: min(cap.width, geo.size.width), height: cap.height)
                    .offset(y: travel * (1 - value))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if start == nil { start = value }
                        value = (start ?? value) - drag.translation.height / travel
                    }
                    .onEnded { _ in start = nil }
            )
            .animation(Motion.press, value: start != nil)
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value / unity * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            value += direction == .increment ? 0.05 : -0.05
        }
    }
}

/// Maps a linear peak to a 0…1 meter position over a 48 dB range.
func meterPosition(_ level: Float) -> Double {
    guard level > 0 else { return 0 }
    let decibels = 20 * log10(Double(level))
    return min(max((decibels + 48) / 48, 0), 1)
}
