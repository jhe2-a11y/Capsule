import XCTest
@testable import Capsule

final class TapIntentTests: XCTestCase {
    func test_parsesUniversalLink() {
        let url = URL(string: "https://capsule.app/c/11111111-1111-1111-1111-111111111111")!
        let intent = TapIntent.parse(url)
        XCTAssertEqual(intent?.capsuleID,
                       UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        XCTAssertNil(intent?.inviteToken)
    }

    func test_parsesUniversalLinkWithInvite() {
        let url = URL(string: "https://capsule.app/c/22222222-2222-2222-2222-222222222222?invite=abc123")!
        let intent = TapIntent.parse(url)
        XCTAssertEqual(intent?.inviteToken, "abc123")
    }

    func test_parsesCustomScheme() {
        let url = URL(string: "capsule://c/33333333-3333-3333-3333-333333333333")!
        let intent = TapIntent.parse(url)
        XCTAssertEqual(intent?.capsuleID,
                       UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
    }

    func test_rejectsNonCapsuleURL() {
        XCTAssertNil(TapIntent.parse(URL(string: "https://capsule.app/about")!))
        XCTAssertNil(TapIntent.parse(URL(string: "https://capsule.app/c/not-a-uuid")!))
    }
}
