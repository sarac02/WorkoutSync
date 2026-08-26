import WorkoutModel
import XCTest
@testable import OverlayKit

@MainActor
final class WorkoutOverlayTimelineTests: XCTestCase {
    private func sample(at t: TimeInterval, hr: Double, energy: Double, distance: Double) -> WorkoutSample {
        WorkoutSample(timestamp: t, heartRate: hr, activeEnergy: energy, distance: distance, sourceDeviceName: "Test")
    }

    func testNoSamplesYieldsNilMetrics() {
        let timeline = WorkoutOverlayTimeline()
        XCTAssertNil(timeline.interpolatedMetrics(atLocalTime: 0))
    }

    func testSingleSampleHoldsItsValueRegardlessOfQueryTime() {
        let timeline = WorkoutOverlayTimeline()
        timeline.ingest(sample(at: 10, hr: 120, energy: 50, distance: 200))

        let early = timeline.interpolatedMetrics(atLocalTime: 0)
        let late = timeline.interpolatedMetrics(atLocalTime: 999)

        XCTAssertEqual(early?.heartRate, 120)
        XCTAssertEqual(late?.heartRate, 120)
    }

    func testInterpolatesLinearlyBetweenTwoBracketingSamples() throws {
        let timeline = WorkoutOverlayTimeline()
        timeline.ingest(sample(at: 0, hr: 100, energy: 0, distance: 0))
        timeline.ingest(sample(at: 10, hr: 140, energy: 100, distance: 1000))

        let midpoint = try XCTUnwrap(timeline.interpolatedMetrics(atLocalTime: 5))

        XCTAssertEqual(midpoint.heartRate, 120, accuracy: 0.001)
        XCTAssertEqual(midpoint.activeEnergy, 50, accuracy: 0.001)
        XCTAssertEqual(midpoint.distance, 500, accuracy: 0.001)
    }

    func testHoldsLastKnownValueWhenQueryTimeIsPastNewestSample() {
        // This is the "don't extrapolate a trend" behavior: querying past
        // the newest sample (e.g. the render tick fired before the next
        // WatchConnectivity message arrived) should hold, not guess.
        let timeline = WorkoutOverlayTimeline()
        timeline.ingest(sample(at: 0, hr: 100, energy: 0, distance: 0))
        timeline.ingest(sample(at: 10, hr: 140, energy: 100, distance: 1000))

        let afterNewest = timeline.interpolatedMetrics(atLocalTime: 15)

        XCTAssertEqual(afterNewest?.heartRate, 140)
    }

    func testBufferDropsOldestSamplesPastCapacity() {
        let timeline = WorkoutOverlayTimeline()
        // maxBufferedSamples is 12; push 20 and confirm only the most
        // recent readings still influence interpolation.
        for i in 0..<20 {
            timeline.ingest(sample(at: TimeInterval(i), hr: Double(i), energy: 0, distance: 0))
        }

        // Sample at t=0 should have been evicted, so querying at t=0 must
        // hold the new *oldest* buffered sample rather than the original.
        let atZero = timeline.interpolatedMetrics(atLocalTime: 0)
        XCTAssertNotEqual(atZero?.heartRate, 0)
    }

    func testIngestKeepsBufferSortedEvenWhenSamplesArriveOutOfOrder() throws {
        let timeline = WorkoutOverlayTimeline()
        timeline.ingest(sample(at: 10, hr: 140, energy: 100, distance: 1000))
        timeline.ingest(sample(at: 0, hr: 100, energy: 0, distance: 0)) // arrives "late" relative to timestamp

        let midpoint = try XCTUnwrap(timeline.interpolatedMetrics(atLocalTime: 5))

        XCTAssertEqual(midpoint.heartRate, 120, accuracy: 0.001)
    }
}
