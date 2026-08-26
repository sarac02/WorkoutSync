import Foundation

/// One timestamped reading of live workout metrics, as a plain Swift value.
///
/// Deliberately has no dependency on WatchConnectivity or any other
/// transport: this type (and `WorkoutSampleSource`) is what OverlayKit and
/// RelayKit build against, so the overlay-rendering code works identically
/// whether the sample arrived over WatchConnectivity (iPhone) or was
/// relayed a second time over Multipeer (Apple TV, which has no Watch
/// pairing of its own).
public struct WorkoutSample: Sendable, Equatable, Codable {
    public let timestamp: TimeInterval
    public let heartRate: Double
    public let activeEnergy: Double
    public let distance: Double
    public let sourceDeviceName: String

    public init(timestamp: TimeInterval, heartRate: Double, activeEnergy: Double, distance: Double, sourceDeviceName: String) {
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.activeEnergy = activeEnergy
        self.distance = distance
        self.sourceDeviceName = sourceDeviceName
    }
}
