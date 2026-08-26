import CTransport
import Foundation
@_exported import WorkoutModel // re-exported so `import TransportKit` alone is enough for app code to name `WorkoutSample`/`WorkoutSampleSource`

/// Swift-facing entry point to the Watch <-> iPhone transport. Wraps the
/// Objective-C++ `WCTransportSession` (WatchConnectivity plumbing, wire
/// framing, clock-offset correction) behind an `AsyncStream` so app code
/// never touches WatchConnectivity directly.
public final class WorkoutTransport: @unchecked Sendable, WorkoutSampleSource {
    public static let shared = WorkoutTransport()

    private let session = WCTransportSession.shared()
    private var continuation: AsyncStream<WorkoutSample>.Continuation?

    /// A live stream of samples received from the counterpart device,
    /// already corrected into this device's local clock. Start iterating
    /// this before the workout begins so no early samples are missed.
    public lazy var incomingSamples: AsyncStream<WorkoutSample> = {
        AsyncStream { continuation in
            self.continuation = continuation
            self.session.activate { [weak self] wireSample in
                guard self != nil else { return }
                continuation.yield(WorkoutSample(wireSample))
            }
        }
    }()

    private init() {}

    /// Sends a sample to the counterpart device. Best-effort and non-blocking;
    /// see `WCTransportSession.sendSample:` for why unreachable counterparts
    /// drop samples instead of queuing them.
    public func send(_ sample: WorkoutSample) {
        session.send(sample.wireSample)
    }

    /// Best current estimate of the clock offset to the counterpart device,
    /// in seconds. Exposed mainly for debugging/telemetry overlays.
    public var estimatedClockOffset: TimeInterval {
        session.estimatedClockOffsetToCounterpart
    }
}
