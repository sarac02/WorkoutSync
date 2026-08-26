import Foundation

/// Why this exists: HealthKit's own recorded workout data is the real
/// physiological record and this package never touches it -- rewriting or
/// discarding what HKWorkoutBuilder actually saves would be actively wrong,
/// since a noisy-but-real reading still belongs in the user's permanent
/// health history. What this *does* gate is what a client chooses to
/// transmit to another device and render live on screen: a single bad optical
/// sensor reading (loose watch band, motion artifact) showing up as "212 BPM"
/// for one frame, then vanishing, is a real, fixable UX problem -- not a
/// health record problem.
public enum HeartRateVerdict: Sendable, Equatable {
    case accepted
    /// Outside any plausible human heart rate, regardless of trend.
    case rejectedOutOfPhysiologicalRange
    /// Within human range, but changed faster than a heart plausibly can
    /// between two consecutive readings -- almost always a sensor artifact
    /// rather than a real physiological event.
    case rejectedImplausibleRateOfChange(bpmPerSecond: Double)
}

public struct HeartRateReading: Sendable, Equatable {
    public let timestamp: TimeInterval
    public let bpm: Double

    public init(timestamp: TimeInterval, bpm: Double) {
        self.timestamp = timestamp
        self.bpm = bpm
    }
}

public struct HeartRateQualityGate: Sendable {
    public let minPlausibleBPM: Double
    public let maxPlausibleBPM: Double

    /// Deliberately asymmetric, not just a rounder number picked for
    /// convenience: sympathetic activation at the onset of effort (e.g. an
    /// explosive sprint start) can drive heart rate up quite fast, but heart
    /// rate *recovery* is comparatively slower -- parasympathetic
    /// reactivation, not an instant drop -- which is well documented in
    /// exercise-physiology heart-rate-recovery (HRR) literature. A real
    /// heart rarely if ever *falls* as fast as it can rise, so a rapid drop
    /// is more likely to be a sensor dropout/glitch than a rapid rise is.
    /// Both ceilings are still deliberately generous safety margins, not a
    /// tight physiological model -- see the README's honest caveat about
    /// this being a heuristic, not real modeling.
    public let maxPlausibleRiseBPMPerSecond: Double
    public let maxPlausibleFallBPMPerSecond: Double

    private var lastAccepted: HeartRateReading?

    public init(
        minPlausibleBPM: Double = 30,
        maxPlausibleBPM: Double = 230,
        maxPlausibleRiseBPMPerSecond: Double = 60,
        maxPlausibleFallBPMPerSecond: Double = 30
    ) {
        self.minPlausibleBPM = minPlausibleBPM
        self.maxPlausibleBPM = maxPlausibleBPM
        self.maxPlausibleRiseBPMPerSecond = maxPlausibleRiseBPMPerSecond
        self.maxPlausibleFallBPMPerSecond = maxPlausibleFallBPMPerSecond
    }

    /// Call once per incoming reading, in timestamp order. Mutates internal
    /// state (the last accepted reading) only when the verdict is
    /// `.accepted`, so a rejected reading doesn't "poison" future
    /// comparisons.
    public mutating func evaluate(_ reading: HeartRateReading) -> HeartRateVerdict {
        guard reading.bpm >= minPlausibleBPM, reading.bpm <= maxPlausibleBPM else {
            return .rejectedOutOfPhysiologicalRange
        }

        if let last = lastAccepted {
            let dt = reading.timestamp - last.timestamp
            if dt > 0 {
                let delta = reading.bpm - last.bpm
                let rateOfChange = delta / dt
                let ceiling = delta >= 0 ? maxPlausibleRiseBPMPerSecond : maxPlausibleFallBPMPerSecond
                if abs(rateOfChange) > ceiling {
                    return .rejectedImplausibleRateOfChange(bpmPerSecond: rateOfChange)
                }
            }
        }

        lastAccepted = reading
        return .accepted
    }
}
