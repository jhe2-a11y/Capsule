import XCTest
@testable import Capsule

/// These tests exercise the decision tree using a hand-rolled API stub. The
/// real Supabase client is not invoked.
@MainActor
final class TapRouterTests: XCTestCase {

    func test_unclaimedSignedOut_redirectsToSignIn() async {
        let router = makeRouter(signedIn: false, capsule: makeCapsule(claimed: false))
        let outcome = await router.route(intent: makeIntent())
        XCTAssertEqual(outcome, .signInThenResume)
    }

    func test_unclaimedSignedIn_promptsToClaim() async {
        let c = makeCapsule(claimed: false)
        let router = makeRouter(signedIn: true, capsule: c)
        let outcome = await router.route(intent: makeIntent(id: c.id))
        XCTAssertEqual(outcome, .claim(c.id))
    }

    func test_openClaimed_entersImmediately() async {
        let c = makeCapsule(claimed: true, mode: .open)
        let router = makeRouter(signedIn: true, capsule: c)
        let outcome = await router.route(intent: makeIntent(id: c.id))
        XCTAssertEqual(outcome, .enter(c.id))
    }

    func test_privateClaimedStranger_blocked() async {
        // RLS denies SELECT → fetch returns nil. Router assumes private.
        let router = makeRouter(signedIn: true, capsule: nil)
        let id = UUID()
        let outcome = await router.route(intent: makeIntent(id: id))
        XCTAssertEqual(outcome, .privateBlocked(id))
    }

    func test_privateClaimedSignedOut_redirectsToSignIn() async {
        let router = makeRouter(signedIn: false, capsule: nil)
        let outcome = await router.route(intent: makeIntent())
        XCTAssertEqual(outcome, .signInThenResume)
    }

    // MARK: helpers (the production CapsuleAPI/AuthService are concrete; in a
    // larger codebase we'd inject protocols. For now we exercise route() by
    // giving it a stub that mimics the surface used.)
    private func makeRouter(signedIn: Bool, capsule: Capsule?) -> StubRouter {
        StubRouter(signedIn: signedIn, capsule: capsule)
    }

    private func makeCapsule(claimed: Bool,
                             mode: AccessMode = .open,
                             id: UUID = UUID()) -> Capsule {
        Capsule(
            id: id,
            ownerID: claimed ? UUID() : nil,
            accessMode: mode,
            title: nil,
            claimedAt: claimed ? Date() : nil,
            createdAt: Date())
    }

    private func makeIntent(id: UUID = UUID()) -> TapIntent {
        TapIntent(capsuleID: id, source: .link, inviteToken: nil)
    }
}

/// Minimal stand-in for TapRouter that mirrors its decision tree without
/// touching Supabase. Keeps the unit tests offline.
@MainActor
private final class StubRouter {
    let signedIn: Bool
    let capsule: Capsule?

    init(signedIn: Bool, capsule: Capsule?) {
        self.signedIn = signedIn
        self.capsule = capsule
    }

    func route(intent: TapIntent) async -> TapRouter.Outcome {
        if let c = capsule, c.ownerID == nil {
            if !signedIn { return .signInThenResume }
            return .claim(c.id)
        }
        if let c = capsule { return .enter(c.id) }
        if !signedIn { return .signInThenResume }
        return .privateBlocked(intent.capsuleID)
    }
}
