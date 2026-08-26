import XCTest
@testable import WorkoutModel

final class WorkoutSampleTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let sample = WorkoutSample(
            timestamp: 123.456,
            heartRate: 142.0,
            activeEnergy: 87.5,
            distance: 612.3,
            sourceDeviceName: "Sara's Apple Watch"
        )

        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(WorkoutSample.self, from: data)

        XCTAssertEqual(decoded, sample)
    }

    func testEqualityIsFieldwise() {
        let a = WorkoutSample(timestamp: 1, heartRate: 100, activeEnergy: 10, distance: 5, sourceDeviceName: "A")
        let b = WorkoutSample(timestamp: 1, heartRate: 100, activeEnergy: 10, distance: 5, sourceDeviceName: "A")
        let c = WorkoutSample(timestamp: 1, heartRate: 101, activeEnergy: 10, distance: 5, sourceDeviceName: "A")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

/// A fake source used by consumers of `WorkoutSampleSource` (OverlayKit,
/// RelayKit) to drive tests without a live transport. Also proves the
/// protocol is satisfiable outside this module.
final class StubWorkoutSampleSource: WorkoutSampleSource, @unchecked Sendable {
    private let continuation: AsyncStream<WorkoutSample>.Continuation
    let incomingSamples: AsyncStream<WorkoutSample>

    init() {
        var continuation: AsyncStream<WorkoutSample>.Continuation!
        incomingSamples = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func emit(_ sample: WorkoutSample) {
        continuation.yield(sample)
    }

    func finish() {
        continuation.finish()
    }
}

final class WorkoutSampleSourceTests: XCTestCase {
    func testStubSourceDeliversEmittedSamples() async {
        let stub = StubWorkoutSampleSource()
        let sample = WorkoutSample(timestamp: 1, heartRate: 120, activeEnergy: 40, distance: 300, sourceDeviceName: "Stub")

        let collected = Task<[WorkoutSample], Never> {
            var results: [WorkoutSample] = []
            for await sample in stub.incomingSamples {
                results.append(sample)
                if results.count == 1 { break }
            }
            return results
        }

        stub.emit(sample)
        let results = await collected.value

        XCTAssertEqual(results, [sample])
    }
}
