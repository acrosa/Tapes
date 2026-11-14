import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TapesLiveBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
    }
}

/// Recording, as seen from the Lock Screen and the Dynamic Island: the display window in
/// miniature. A lit record lamp, the track, the tape's name, and the counter running.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        RecordLamp(size: 8)
                        Text("REC \(context.state.track)")
                            .font(LiveTheme.mono("Medium", 12))
                            .tracking(0.2)
                            .foregroundStyle(LiveTheme.signal)
                    }
                    Text(context.attributes.tapeName)
                        .font(LiveTheme.mono("Regular", 12))
                        .foregroundStyle(LiveTheme.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Counter(from: context.state.tapeZero, size: 40)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .activityBackgroundTint(LiveTheme.glass)
            .activitySystemActionForegroundColor(LiveTheme.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        RecordLamp(size: 8)
                        Text("REC \(context.state.track)")
                            .font(LiveTheme.mono("Medium", 12))
                            .foregroundStyle(LiveTheme.signal)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Counter(from: context.state.tapeZero, size: 28)
                        .frame(maxWidth: 110, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.tapeName)
                        .font(LiveTheme.mono("Regular", 12))
                        .foregroundStyle(LiveTheme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
            } compactLeading: {
                RecordLamp(size: 8)
            } compactTrailing: {
                Counter(from: context.state.tapeZero, size: 13)
                    .frame(maxWidth: 44)
            } minimal: {
                RecordLamp(size: 8)
            }
            .keylineTint(LiveTheme.signal)
        }
    }
}

/// The record lamp, lit.
private struct RecordLamp: View {
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(LiveTheme.signal)
            .frame(width: size, height: size)
            .shadow(color: LiveTheme.signal.opacity(0.7), radius: size / 2)
    }
}

/// The tape counter. The system advances it, so it keeps time while the app is in the background.
private struct Counter: View {
    var from: Date
    var size: CGFloat

    var body: some View {
        Text(timerInterval: from...Date.distantFuture, countsDown: false)
            .font(LiveTheme.mono("Light", size))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .foregroundStyle(LiveTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
