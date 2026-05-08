import XCTest
@testable import Capsule

@MainActor
final class FocusControllerTests: XCTestCase {
    func test_focusThenDismissReturnsToBrowsing() async throws {
        let fc = FocusController()
        let id = UUID()
        XCTAssertEqual(fc.state, .browsing)

        fc.focus(id, currentZ: 0.5)
        if case .settling(let mid) = fc.state {
            XCTAssertEqual(mid, id)
        } else { XCTFail("expected settling") }

        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertEqual(fc.focusedMemoryID, id)

        fc.dismiss()
        XCTAssertEqual(fc.dolly, 0)

        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertEqual(fc.state, .browsing)
    }

    func test_dollyComputedToBringNodeToForeground() {
        let fc = FocusController()
        fc.focus(UUID(), currentZ: 0.4)
        XCTAssertEqual(fc.dolly, 0.55, accuracy: 0.001)
    }
}
