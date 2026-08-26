import XCTest
@testable import CaptureGuard

final class SensorDropoutMonitorTests: XCTestCase {
    func testNotDroppedShortlyAfterASample() {
        var monitor = SensorDropoutMonitor(dropoutThreshold: 15)
        monitor.recordSample(at: 100)
        XCTAssertFalse(monitor.isDropped(asOf: 105))
    }

    func testDroppedAfterThresholdElapsesWithNoNewSample() {
        var monitor = SensorDropoutMonitor(dropoutThreshold: 15)
        monitor.recordSample(at: 100)
        XCTAssertTrue(monitor.isDropped(asOf: 120))
    }

    func testConsideredDroppedBeforeAnySampleHasArrived() {
        let monitor = SensorDropoutMonitor(dropoutThreshold: 15)
        XCTAssertTrue(monitor.isDropped(asOf: 0))
    }

    func testRecordingANewSampleClearsTheDropoutState() {
        var monitor = SensorDropoutMonitor(dropoutThreshold: 15)
        monitor.recordSample(at: 100)
        XCTAssertTrue(monitor.isDropped(asOf: 120))
        monitor.recordSample(at: 121)
        XCTAssertFalse(monitor.isDropped(asOf: 122))
    }
}
