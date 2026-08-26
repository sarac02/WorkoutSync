import Foundation

/// Detects when heart-rate updates have gone quiet for longer than a real
/// sensor should during an active workout -- e.g. the Watch has lost skin
/// contact. This doesn't reject any data itself; it's a signal the app
/// layer can use to show "checking heart rate..." instead of silently
/// freezing on the last good number as if everything's fine.
public struct SensorDropoutMonitor: Sendable {
    public let dropoutThreshold: TimeInterval
    private var lastSampleTime: TimeInterval?

    public init(dropoutThreshold: TimeInterval = 15) {
        self.dropoutThreshold = dropoutThreshold
    }

    public mutating func recordSample(at time: TimeInterval) {
        lastSampleTime = time
    }

    /// True if it's been longer than `dropoutThreshold` since the last
    /// recorded sample -- or if no sample has ever been recorded.
    public func isDropped(asOf now: TimeInterval) -> Bool {
        guard let last = lastSampleTime else { return true }
        return now - last > dropoutThreshold
    }
}
