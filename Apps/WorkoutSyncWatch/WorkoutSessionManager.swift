import CaptureGuard
import Foundation
import HealthKit
import Observation
import TransportKit
import WatchKit

/// Runs an `HKWorkoutSession` on the Watch, reads heart rate / active energy
/// / distance as they're collected, and streams each update to the iPhone
/// over `WorkoutTransport` in real time. This is the source end of the
/// pipeline the JD describes: "low level communication to send workout data
/// between devices" starts here, at the HealthKit live workout builder.
///
/// This does **not** alter what HealthKit actually records -- `builder`
/// still collects and saves the real, unfiltered sensor data via
/// `finishWorkout`. `CaptureGuard` only gates what gets held in
/// `currentHeartRate`/etc. and therefore transmitted/displayed: a single
/// glitchy optical-sensor spike is a live-UX problem worth catching, but
/// silently editing the permanent health record would not be.
@MainActor
@Observable
final class WorkoutSessionManager: NSObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private var heartRateGate = HeartRateQualityGate()
    private var energyGuard = CumulativeMetricGuard()
    private var distanceGuard = CumulativeMetricGuard()
    private var dropoutMonitor = SensorDropoutMonitor()
    private var dropoutCheckTask: Task<Void, Never>?

    private(set) var isRunning = false
    private(set) var currentHeartRate: Double = 0
    private(set) var currentActiveEnergy: Double = 0
    private(set) var currentDistance: Double = 0
    /// True once heart-rate updates have gone quiet longer than a real
    /// sensor reading a wrist should -- e.g. a loose watch band. The UI can
    /// show "checking heart rate..." instead of silently freezing on the
    /// last good number as if nothing's wrong.
    private(set) var isHeartRateSignalStale = false
    /// Human-readable reason the most recent heart-rate reading was held
    /// back, if any -- surfaced in the UI mainly so this behavior is
    /// visible/demonstrable rather than a silent no-op.
    private(set) var lastRejectedHeartRateReason: String?
    /// Set if `HKWorkoutSession` itself fails -- most commonly because
    /// live workout sessions are only partially supported in the watchOS
    /// Simulator (no real extended-runtime-session/workout daemon), not
    /// because of anything this app does wrong. Surfaced so a failure is
    /// visible in the UI instead of silently doing nothing while the
    /// console fills with HealthKit state-machine errors.
    private(set) var sessionError: String?

    func requestAuthorization() async throws {
        let typesToShare: Set<HKSampleType> = [HKQuantityType.workoutType()]
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning)
        ]
        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
    }

    func start() throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .indoor

        let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let newBuilder = newSession.associatedWorkoutBuilder()
        newBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

        newSession.delegate = self
        newBuilder.delegate = self

        session = newSession
        builder = newBuilder

        heartRateGate = HeartRateQualityGate()
        energyGuard = CumulativeMetricGuard()
        distanceGuard = CumulativeMetricGuard()
        dropoutMonitor = SensorDropoutMonitor()
        isHeartRateSignalStale = false
        lastRejectedHeartRateReason = nil
        sessionError = nil

        let startDate = Date()
        newSession.startActivity(with: startDate)
        newBuilder.beginCollection(withStart: startDate) { [weak self] success, _ in
            Task { @MainActor in self?.isRunning = success }
        }

        dropoutCheckTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.isHeartRateSignalStale = self.dropoutMonitor.isDropped(asOf: workoutSyncMonotonicTime())
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        session?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            // HealthKit calls this completion on an arbitrary queue, not
            // necessarily the main actor -- hop back before touching
            // `builder`, which is main-actor-isolated state. (There's no
            // completion-free async overload of finishWorkout on
            // HKLiveWorkoutBuilder to use instead, despite the compiler's
            // "consider using asynchronous alternative" nudge -- verified
            // by trying it, not assumed.)
            Task { @MainActor in
                self?.builder?.finishWorkout { _, _ in }
            }
        }
        dropoutCheckTask?.cancel()
        isRunning = false
    }

    private func handleUpdatedStatistics(_ statistics: HKStatistics) {
        switch statistics.quantityType {
        case HKQuantityType(.heartRate):
            let unit = HKUnit.count().unitDivided(by: .minute())
            guard let rawBPM = statistics.mostRecentQuantity()?.doubleValue(for: unit) else { return }
            handleHeartRateReading(rawBPM)
        case HKQuantityType(.activeEnergyBurned):
            let rawEnergy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? currentActiveEnergy
            currentActiveEnergy = energyGuard.accept(rawEnergy)
        case HKQuantityType(.distanceWalkingRunning):
            let rawDistance = statistics.sumQuantity()?.doubleValue(for: .meter()) ?? currentDistance
            currentDistance = distanceGuard.accept(rawDistance)
        default:
            return
        }
        sendSample()
    }

    private func handleHeartRateReading(_ rawBPM: Double) {
        let now = workoutSyncMonotonicTime()
        let verdict = heartRateGate.evaluate(HeartRateReading(timestamp: now, bpm: rawBPM))

        switch verdict {
        case .accepted:
            currentHeartRate = rawBPM
            dropoutMonitor.recordSample(at: now)
            lastRejectedHeartRateReason = nil
        case .rejectedOutOfPhysiologicalRange:
            // Held back entirely: a reading outside human range is never
            // useful, so `currentHeartRate` keeps its last good value.
            lastRejectedHeartRateReason = "reading of \(Int(rawBPM)) BPM is outside plausible human range"
        case .rejectedImplausibleRateOfChange(let rate):
            lastRejectedHeartRateReason = "reading changed \(Int(rate)) BPM/s -- faster than physiologically plausible"
        }
    }

    private func sendSample() {
        let sample = WorkoutSample(
            timestamp: workoutSyncMonotonicTime(),
            heartRate: currentHeartRate,
            activeEnergy: currentActiveEnergy,
            distance: currentDistance,
            sourceDeviceName: WKInterfaceDevice.current().name
        )
        WorkoutTransport.shared.send(sample)
    }
}

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        if toState == .stopped || toState == .ended {
            Task { @MainActor in
                self.isRunning = false
                self.dropoutCheckTask?.cancel()
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.sessionError = error.localizedDescription
            self.isRunning = false
            self.dropoutCheckTask?.cancel()
        }
    }
}

extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
            Task { @MainActor in
                self.handleUpdatedStatistics(statistics)
            }
        }
    }
}
