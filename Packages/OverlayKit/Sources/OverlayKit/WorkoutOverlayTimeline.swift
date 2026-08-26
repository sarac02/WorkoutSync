import Foundation
import Observation
import WireCodec
import WorkoutModel

/// The metrics an overlay renders at one instant, after interpolation.
public struct InterpolatedWorkoutMetrics: Sendable, Equatable {
    public let heartRate: Double
    public let activeEnergy: Double
    public let distance: Double
}

/// Turns a sparse, irregular stream of `WorkoutSample`s (WatchConnectivity
/// delivers roughly once a second, not once a frame) into a smooth 30fps
/// signal the overlay views can animate against.
///
/// This is the piece that makes "render live data as a video overlay" hard:
/// samples arrive late, out of order relative to wall clock jitter, and
/// sometimes not at all for a couple of seconds. Naively binding a Text view
/// straight to the latest sample makes the heart-rate number visibly stutter
/// and jump. Instead this buffers the last dozen samples and linearly
/// interpolates between the two that bracket "now", holding the last known
/// value rather than extrapolating when there's nothing to interpolate
/// towards yet.
/// `@MainActor`-isolated deliberately: `start()` spawns two unstructured
/// `Task`s (one ingesting samples, one ticking the render loop), and both
/// touch `buffer`. Without a shared isolation domain those would be a real
/// data race -- two tasks mutating/reading a plain `Array` concurrently from
/// arbitrary threads, not just a theoretical one. Pinning the whole class to
/// the main actor means both `Task { ... }` closures below inherit that
/// isolation and never actually run concurrently with each other, which
/// costs nothing here since `latest` needs to reach SwiftUI on the main
/// actor anyway.
@MainActor
@Observable
public final class WorkoutOverlayTimeline {
    public private(set) var latest: InterpolatedWorkoutMetrics?

    private var buffer: [WorkoutSample] = []
    private let maxBufferedSamples = 12
    private let renderHz: UInt64 = 30

    private var ingestTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    public init() {}

    /// - Parameter source: where samples come from. Pass
    ///   `TransportKit.WorkoutTransport.shared` on iPhone (direct
    ///   WatchConnectivity to the Watch), or a `RelayKit.WorkoutRelayClient`
    ///   on tvOS, which has no WatchConnectivity of its own and instead
    ///   receives samples relayed over the local network by the iPhone.
    ///   OverlayKit deliberately doesn't default this to a concrete
    ///   transport -- doing so would pull WatchConnectivity into the tvOS
    ///   build, which doesn't support it.
    public func start(source: any WorkoutSampleSource) {
        ingestTask = Task { [weak self] in
            for await sample in source.incomingSamples {
                guard let self else { return }
                self.ingest(sample)
            }
        }
        tickTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.latest = self.interpolatedMetrics(atLocalTime: wc_monotonic_time())
                try? await Task.sleep(nanoseconds: 1_000_000_000 / self.renderHz)
            }
        }
    }

    public func stop() {
        ingestTask?.cancel()
        tickTask?.cancel()
    }

    // `internal` rather than `private` so OverlayKitTests can drive the
    // interpolation math directly with fabricated timestamps instead of
    // waiting on real wall-clock ticks through the public start()/stop() API.
    func ingest(_ sample: WorkoutSample) {
        buffer.append(sample)
        buffer.sort { $0.timestamp < $1.timestamp }
        if buffer.count > maxBufferedSamples {
            buffer.removeFirst(buffer.count - maxBufferedSamples)
        }
    }

    func interpolatedMetrics(atLocalTime time: TimeInterval) -> InterpolatedWorkoutMetrics? {
        guard let first = buffer.first, let last = buffer.last else { return nil }

        if buffer.count == 1 || time >= last.timestamp {
            // Hold the last known reading instead of extrapolating a trend --
            // showing a plausible-looking but wrong heart rate for a couple
            // of seconds is worse than a value that briefly stops updating.
            return InterpolatedWorkoutMetrics(heartRate: last.heartRate, activeEnergy: last.activeEnergy, distance: last.distance)
        }
        if time <= first.timestamp {
            return InterpolatedWorkoutMetrics(heartRate: first.heartRate, activeEnergy: first.activeEnergy, distance: first.distance)
        }

        guard let upperIndex = buffer.firstIndex(where: { $0.timestamp >= time }), upperIndex > 0 else {
            return InterpolatedWorkoutMetrics(heartRate: last.heartRate, activeEnergy: last.activeEnergy, distance: last.distance)
        }
        let upper = buffer[upperIndex]
        let lower = buffer[upperIndex - 1]
        let span = upper.timestamp - lower.timestamp
        let fraction = span > 0 ? (time - lower.timestamp) / span : 0

        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * fraction }

        return InterpolatedWorkoutMetrics(
            heartRate: lerp(lower.heartRate, upper.heartRate),
            activeEnergy: lerp(lower.activeEnergy, upper.activeEnergy),
            distance: lerp(lower.distance, upper.distance)
        )
    }
}
