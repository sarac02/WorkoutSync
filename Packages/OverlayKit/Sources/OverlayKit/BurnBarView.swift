import SwiftUI

/// Fitness+'s "Burn Bar": shows how the current session's cumulative active
/// energy compares to a reference value (e.g. the average across everyone
/// who's done this workout before). `referenceEnergy` is a static number
/// baked into the workout's metadata in the real app; here it's just passed
/// in so the view stays decoupled from wherever that number comes from.
public struct BurnBarView: View {
    public let currentEnergy: Double
    public let referenceEnergy: Double

    public init(currentEnergy: Double, referenceEnergy: Double) {
        self.currentEnergy = currentEnergy
        self.referenceEnergy = referenceEnergy
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))

                Capsule()
                    .fill(barColor)
                    .frame(width: proxy.size.width * fraction)
                    .animation(.easeOut(duration: 0.4), value: fraction)

                // Reference marker: where "the average person" is right now.
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .offset(x: proxy.size.width * 0.5 - 1)
                    .opacity(0.8)
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
    }

    private var fraction: Double {
        guard referenceEnergy > 0 else { return 0 }
        // Reference sits at the midpoint of the bar; current energy can push
        // past it in either direction, clamped so the fill never overflows.
        return min(max(currentEnergy / (referenceEnergy * 2), 0), 1)
    }

    private var barColor: Color {
        currentEnergy >= referenceEnergy ? .green : .orange
    }
}
