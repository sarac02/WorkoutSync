import SwiftUI

/// The live heart-rate readout that appears when the trainer says "check
/// your heart rate" -- an animated pulse icon plus a number that eases
/// between values instead of snapping, using `WorkoutOverlayTimeline`'s
/// interpolated stream as its input.
public struct HeartRateTickerView: View {
    public let heartRate: Double?

    public init(heartRate: Double?) {
        self.heartRate = heartRate
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating.speed(pulseSpeed), isActive: heartRate != nil)

            Text(displayValue)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: displayValue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45), in: Capsule())
    }

    private var displayValue: String {
        guard let heartRate else { return "--" }
        return String(Int(heartRate.rounded()))
    }

    /// Maps BPM onto the pulse animation's speed so the icon beats roughly
    /// in time with the actual heart rate rather than at a fixed cadence.
    private var pulseSpeed: Double {
        guard let heartRate, heartRate > 0 else { return 1.0 }
        return heartRate / 70.0
    }
}
