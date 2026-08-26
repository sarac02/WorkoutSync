import WorkoutModel
import XCTest
@testable import RelayKit

final class RelayWireFormatTests: XCTestCase {
    func testSampleEncodeDecodeRoundTrip() throws {
        let sample = WorkoutSample(timestamp: 42, heartRate: 133, activeEnergy: 60, distance: 400, sourceDeviceName: "iPhone")

        let tagged = try XCTUnwrap(RelayWireFormat.encodeSample(sample))
        let (tag, payload) = try XCTUnwrap(RelayWireFormat.untag(tagged))

        XCTAssertEqual(tag, .sample)
        XCTAssertEqual(RelayWireFormat.decodeSample(from: payload), sample)
    }

    func testDecodeSampleRejectsGarbagePayload() {
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertNil(RelayWireFormat.decodeSample(from: garbage))
    }

    func testUntagRejectsEmptyData() {
        XCTAssertNil(RelayWireFormat.untag(Data()))
    }

    func testUntagRejectsAnUnrecognizedTagByte() {
        XCTAssertNil(RelayWireFormat.untag(Data([0xFF])))
    }

    func testTimestampEncodeDecodeRoundTrip() {
        let value = 12345.6789
        XCTAssertEqual(RelayWireFormat.decodeTimestamp(RelayWireFormat.encodeTimestamp(value)), value)
    }

    func testDecodeTimestampRejectsTooFewBytes() {
        XCTAssertNil(RelayWireFormat.decodeTimestamp(Data([0x01, 0x02])))
    }
}

final class RelayServiceTypeTests: XCTestCase {
    /// MultipeerConnectivity's serviceType has hard constraints (1-15 chars,
    /// lowercase ASCII letters/numbers/hyphens); getting this wrong fails
    /// silently at runtime with peers that just never discover each other,
    /// so it's worth pinning down in a test rather than trusting instinct.
    func testServiceTypeSatisfiesMultipeerConnectivityConstraints() {
        let name = RelayServiceType.name

        XCTAssertFalse(name.isEmpty)
        XCTAssertLessThanOrEqual(name.count, 15)
        XCTAssertTrue(name.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
    }
}
