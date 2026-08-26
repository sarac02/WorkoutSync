import Foundation

/// Anything that can hand out a live stream of `WorkoutSample`s.
///
/// `TransportKit.WorkoutTransport` (WatchConnectivity, iPhone <-> Watch) and
/// `RelayKit.WorkoutRelayClient` (Multipeer, Apple TV <-> iPhone) both
/// conform to this, so `OverlayKit.WorkoutOverlayTimeline` can drive the
/// same overlay UI from either source without knowing which device it's
/// running on.
public protocol WorkoutSampleSource: Sendable {
    var incomingSamples: AsyncStream<WorkoutSample> { get }
}
