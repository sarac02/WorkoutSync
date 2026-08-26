import Foundation

/// Active energy and distance are cumulative for the lifetime of a workout
/// -- they should only ever hold steady or increase. A decrease almost
/// always means a stale/out-of-order statistics callback (HealthKit can
/// deliver updates slightly out of order) rather than the user's calorie
/// burn actually reversing, so treating it as "hold the last good value"
/// is both simpler and more correct than displaying a number that visibly
/// goes backwards.
public struct CumulativeMetricGuard: Sendable {
    private var lastAccepted: Double = 0

    public init() {}

    /// Returns the value to actually use: `candidate` if it's consistent
    /// with a cumulative metric, otherwise the last accepted value.
    public mutating func accept(_ candidate: Double) -> Double {
        if candidate >= lastAccepted {
            lastAccepted = candidate
        }
        return lastAccepted
    }
}
