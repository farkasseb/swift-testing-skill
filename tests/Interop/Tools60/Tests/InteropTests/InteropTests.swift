// A failing XCTest assertion inside a Swift Testing test.
// run.sh checks whether the test passes or fails under each interop mode.
import Testing
import XCTest

@Test func xctAssertInsideTest() {
    XCTAssertEqual(1, 2, "interop probe")
}
