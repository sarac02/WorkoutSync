import CTransport
import WorkoutModel
import XCTest
@testable import TransportKit

/// NOTE: this target links CTransport, which imports WatchConnectivity --
/// only available on iOS/watchOS. Run it against an iOS/watchOS
/// destination (`cd Packages/TransportKit && xcodebuild test -scheme
/// TransportKit -destination 'platform=iOS Simulator,name=...'`), not plain
/// `swift test`, which always builds for the host Mac. See README.md.
final class WorkoutSampleWireTests: XCTestCase {
    func testRoundTripsThroughTheObjCWireTypeUnchanged() {
        let original = WorkoutSample(
            timestamp: 1234.5,
            heartRate: 156.0,
            activeEnergy: 220.75,
            distance: 3800.0,
            sourceDeviceName: "Sara's Apple Watch"
        )

        let wire = original.wireSample
        let roundTripped = WorkoutSample(wire)

        XCTAssertEqual(roundTripped, original)
    }

    func testPackedDataRoundTripsThroughWTSample() {
        let original = WorkoutSample(timestamp: 1, heartRate: 90, activeEnergy: 5, distance: 12, sourceDeviceName: "Watch")
        let wire = original.wireSample

        let packed = wire.packedData()
        let unpacked = WTSample.unpack(from: packed)

        XCTAssertNotNil(unpacked)
        XCTAssertEqual(unpacked.map(WorkoutSample.init), original)
    }
}
