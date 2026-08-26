import XCTest
@testable import WireCodec

final class WireSampleCodecTests: XCTestCase {
    func testEncodeDecodeRoundTrip() {
        var sample = WCSampleWire()
        sample.timestamp = 123.5
        sample.heartRate = 142.0
        sample.activeEnergy = 87.25
        sample.distance = 610.0
        withUnsafeMutableBytes(of: &sample.sourceDeviceName) { raw in
            "Sara's Apple Watch".utf8CString.withUnsafeBytes { src in
                raw.copyBytes(from: src.prefix(raw.count))
            }
        }

        var buffer = [UInt8](repeating: 0, count: wc_wire_sample_size())
        wc_encode_sample(&sample, &buffer)

        var decoded = WCSampleWire()
        let ok = wc_decode_sample(&buffer, buffer.count, &decoded) == 1

        XCTAssertTrue(ok)
        XCTAssertEqual(decoded.timestamp, sample.timestamp)
        XCTAssertEqual(decoded.heartRate, sample.heartRate)
        XCTAssertEqual(decoded.activeEnergy, sample.activeEnergy)
        XCTAssertEqual(decoded.distance, sample.distance)
    }

    func testDecodeRejectsTruncatedBuffer() {
        var buffer = [UInt8](repeating: 0, count: wc_wire_sample_size() - 1)
        var decoded = WCSampleWire()
        let ok = wc_decode_sample(&buffer, buffer.count, &decoded) == 1
        XCTAssertFalse(ok)
    }
}

final class ClockOffsetEstimatorTests: XCTestCase {
    func testNoEstimateBeforeAnyProbes() {
        let estimator = wc_clock_estimator_create(9)
        defer { wc_clock_estimator_destroy(estimator) }

        XCTAssertEqual(wc_clock_estimator_has_estimate(estimator), 0)
        XCTAssertEqual(wc_clock_estimator_median_offset(estimator), 0.0)
    }

    /// If the peer's clock reads exactly 5s ahead of ours and the round
    /// trip is symmetric, the estimator should recover an offset of ~5s
    /// regardless of how much absolute time has passed.
    func testRecoversKnownOffsetFromSymmetricRoundTrips() {
        let estimator = wc_clock_estimator_create(9)
        defer { wc_clock_estimator_destroy(estimator) }

        let peerLead = 5.0
        for i in 0..<5 {
            let t0 = Double(i) * 4.0
            let networkDelay = 0.05
            let t2 = t0 + networkDelay * 2
            let tPeer = t0 + networkDelay + peerLead
            wc_clock_estimator_add_probe(estimator, t0, tPeer, t2)
        }

        XCTAssertEqual(wc_clock_estimator_has_estimate(estimator), 1)
        XCTAssertEqual(wc_clock_estimator_median_offset(estimator), -peerLead, accuracy: 0.001)
    }

    func testMedianIsRobustToOneOutlierProbe() {
        let estimator = wc_clock_estimator_create(5)
        defer { wc_clock_estimator_destroy(estimator) }

        // Four consistent probes agreeing on a ~2s offset...
        for i in 0..<4 {
            let t0 = Double(i) * 4.0
            wc_clock_estimator_add_probe(estimator, t0, t0 + 2.0, t0)
        }
        // ...and one wildly slow probe that would badly skew a mean.
        wc_clock_estimator_add_probe(estimator, 100.0, 100.0 + 900.0, 100.0)

        XCTAssertEqual(wc_clock_estimator_median_offset(estimator), -2.0, accuracy: 0.001)
    }
}
