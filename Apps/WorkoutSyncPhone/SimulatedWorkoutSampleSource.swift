import Foundation
import TransportKit

/// Feeds fabricated, gradually-changing samples through the exact same
/// `WorkoutSampleSource` pipeline real Watch data uses. WatchConnectivity
/// and HealthKit don't produce real live data in the Simulator, so without
/// this the overlay would just sit frozen at "--" -- this exists purely so
/// the rendering/interpolation pipeline is visibly demonstrable without a
/// physical Watch.
final class SimulatedWorkoutSampleSource: WorkoutSampleSource, @unchecked Sendable {
    private let continuation: AsyncStream<WorkoutSample>.Continuation
    let incomingSamples: AsyncStream<WorkoutSample>
    private var task: Task<Void, Never>?

    init() {
        var continuation: AsyncStream<WorkoutSample>.Continuation!
        incomingSamples = AsyncStream { continuation = $0 }
        self.continuation = continuation

        task = Task { [continuation] in
            var energy = 0.0
            var distance = 0.0
            var tick = 0.0
            while !Task.isCancelled {
                let heartRate = 120 + 25 * sin(tick / 8.0)
                energy += 0.35
                distance += 2.2
                continuation!.yield(WorkoutSample(
                    timestamp: workoutSyncMonotonicTime(),
                    heartRate: heartRate,
                    activeEnergy: energy,
                    distance: distance,
                    sourceDeviceName: "Simulated Watch"
                ))
                tick += 1
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    deinit {
        task?.cancel()
    }
}
