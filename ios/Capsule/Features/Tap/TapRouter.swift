import Foundation

/// Decision tree run when the user taps a Capsule (NFC) or follows a deep
/// link. Pure logic — no UI — to keep it unit-testable.
@MainActor
final class TapRouter {
    enum Outcome: Equatable {
        case signInThenResume
        case claim(UUID)
        case enter(UUID)
        case privateBlocked(UUID)
        case notFound
    }

    private let api: CapsuleAPI
    private let auth: AuthService

    init(api: CapsuleAPI, auth: AuthService) {
        self.api = api
        self.auth = auth
    }

    func route(intent: TapIntent) async -> Outcome {
        // 1. Invite token: try to redeem first; on success, the user becomes
        //    a collaborator and we enter directly.
        if let token = intent.inviteToken, auth.user != nil {
            if let id = try? await api.redeemInvite(token: token) {
                return .enter(id)
            }
        }

        // 2. Fetch the capsule. If RLS denies (private + not collaborator),
        //    we still need to know if it exists to surface privateBlocked vs
        //    notFound. With anon access RLS will return nil for private rows.
        let capsule: Capsule?
        do {
            capsule = try await api.fetchCapsule(id: intent.capsuleID)
        } catch {
            return .notFound
        }

        // 3. Unclaimed → claim flow (auth required first).
        if let c = capsule, c.ownerID == nil {
            if auth.user == nil { return .signInThenResume }
            return .claim(c.id)
        }

        // 4. Visible (open mode, owner, or collaborator) → enter.
        if let c = capsule {
            return .enter(c.id)
        }

        // 5. Capsule not visible: either it's private and we're not a
        //    collaborator, or it doesn't exist. If signed-out, ask to sign
        //    in (the row may belong to them or they may have an invite); if
        //    signed-in, treat as private-blocked (the better failure mode
        //    than a misleading "not found").
        if auth.user == nil { return .signInThenResume }
        return .privateBlocked(intent.capsuleID)
    }
}
