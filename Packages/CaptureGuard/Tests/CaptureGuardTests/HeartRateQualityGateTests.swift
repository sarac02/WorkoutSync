import XCTest
@testable import CaptureGuard

final class HeartRateQualityGateTests: XCTestCase {
    func testAcceptsAPlausibleGradualRise() {
        var gate = HeartRateQualityGate()
        XCTAssertEqual(gate.evaluate(HeartRateReading(timestamp: 0, bpm: 90)), .accepted)
        // +20 BPM over 4 seconds = 5 BPM/s, well under the 60 BPM/s ceiling.
        XCTAssertEqual(gate.evaluate(HeartRateReading(timestamp: 4, bpm: 110)), .accepted)
    }

    func testRejectsAnImpossibleInstantSpike() {
        var gate = HeartRateQualityGate()
        XCTAssertEqual(gate.evaluate(HeartRateReading(timestamp: 0, bpm: 95)), .accepted)
        // +110 BPM in 1 second: a sensor artifact, not a real heartbeat.
        let verdict = gate.evaluate(HeartRateReading(timestamp: 1, bpm: 205))
        guard case .rejectedImplausibleRateOfChange(let rate) = verdict else {
            return XCTFail("expected rejectedImplausibleRateOfChange, got \(verdict)")
        }
        XCTAssertEqual(rate, 110, accuracy: 0.001)
    }

    func testRejectsOutOfPhysiologicalRangeRegardlessOfTrend() {
        var gate = HeartRateQualityGate()
        XCTAssertEqual(gate.evaluate(HeartRateReading(timestamp: 0, bpm: 12)), .rejectedOutOfPhysiologicalRange)
        XCTAssertEqual(gate.evaluate(HeartRateReading(timestamp: 1, bpm: 999)), .rejectedOutOfPhysiologicalRange)
    }

    func testARejectedReadingDoesNotPoisonTheNextComparison() {
        var gate = HeartRateQualityGate()
        XCTAssertEqual(gate.evaluate(HeartRateReading(timestamp: 0, bpm: 100)), .accepted)

        // A glitchy spike gets rejected...
        let spike = gate.evaluate(HeartRateReading(timestamp: 1, bpm: 250))
        if case .accepted = spike { XCTFail("the spike itself should have been rejected") }

        // ...and the *next* real reading is still compared against the last
        // *accepted* value (100), not the rejected spike (250), so a normal
        // reading right after a glitch isn't wrongly rejected too.
        XCTAssertEqual(gate.evaluate(HeartRateReading(timestamp: 2, bpm: 104)), .accepted)
    }

    func testLargeRateOfChangeOverALongerGapIsAccepted() {
        // Same 20 BPM delta as the "plausible" test, but this time
        // instantaneous-looking because it's the very first reading with
        // no prior comparison point -- should not be penalized.
        var gate = HeartRateQualityGate()
        XCTAssertEqual(gate.evaluate(HeartRateReading(timestamp: 100, bpm: 140)), .accepted)
    }

    func testTheFallCeilingIsStricterThanTheRiseCeiling() {
        var gate = HeartRateQualityGate()
        XCTAssertEqual(gate.evaluate(HeartRateReading(timestamp: 0, bpm: 150)), .accepted)

        // -40 BPM in 1 second: under the default rise ceiling (60) but over
        // the default fall ceiling (30) -- a drop this fast is less
        // physiologically plausible than an equal-magnitude rise.
        let verdict = gate.evaluate(HeartRateReading(timestamp: 1, bpm: 110))
        guard case .rejectedImplausibleRateOfChange(let rate) = verdict else {
            return XCTFail("expected rejectedImplausibleRateOfChange, got \(verdict)")
        }
        XCTAssertEqual(rate, -40, accuracy: 0.001)
    }

    func testARiseOfTheSameMagnitudeThatWouldRejectAFallIsAccepted() {
        var gate = HeartRateQualityGate()
        XCTAssertEqual(gate.evaluate(HeartRateReading(timestamp: 0, bpm: 100)), .accepted)
        // +40 BPM in 1 second: under the rise ceiling (60), even though a
        // -40 BPM/s fall (see above) is rejected.
        XCTAssertEqual(gate.evaluate(HeartRateReading(timestamp: 1, bpm: 140)), .accepted)
    }
}
