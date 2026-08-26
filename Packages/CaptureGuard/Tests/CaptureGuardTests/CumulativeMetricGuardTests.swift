import XCTest
@testable import CaptureGuard

final class CumulativeMetricGuardTests: XCTestCase {
    func testIncreasingValuesAreAcceptedAsIs() {
        var guard_ = CumulativeMetricGuard()
        XCTAssertEqual(guard_.accept(10), 10)
        XCTAssertEqual(guard_.accept(25), 25)
        XCTAssertEqual(guard_.accept(25), 25) // holding steady is fine too
    }

    func testADecreaseHoldsTheLastAcceptedValueInstead() {
        var guard_ = CumulativeMetricGuard()
        XCTAssertEqual(guard_.accept(100), 100)
        // A stale/out-of-order callback reporting less than before...
        XCTAssertEqual(guard_.accept(80), 100)
        // ...and a later, genuinely higher value still moves it forward.
        XCTAssertEqual(guard_.accept(120), 120)
    }
}
