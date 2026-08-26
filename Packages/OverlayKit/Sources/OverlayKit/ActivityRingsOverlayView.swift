import SwiftUI

/// A simplified, single-ring take on Apple Watch's Activity Rings: fills as
/// `currentEnergy` approaches `goalEnergy`, then plays a brief celebration
/// when it closes. Real Fitness+ shows all three rings pulled from HealthKit;
/// this overlay only has the energy figure available from the live sample
/// stream, so it renders just the Move ring rather than faking Exercise/Stand
/// data it doesn't actually have.
public struct ActivityRingsOverlayView: View {
    public let currentEnergy: Double
    public let goalEnergy: Double

    @State private var didCelebrate = false

    public init(currentEnergy: Double, goalEnergy: Double) {
        self.currentEnergy = currentEnergy
        self.goalEnergy = goalEnergy
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 10)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(.red, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: progress)

            if didCelebrate {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 56, height: 56)
        .onChange(of: progress) { _, newValue in
            if newValue >= 1.0 && !didCelebrate {
                withAnimation(.bouncy) { didCelebrate = true }
            } else if newValue < 1.0 {
                didCelebrate = false
            }
        }
    }

    private var progress: Double {
        guard goalEnergy > 0 else { return 0 }
        return min(currentEnergy / goalEnergy, 1.0)
    }
}
