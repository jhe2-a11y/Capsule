import Foundation
import SwiftUI

@MainActor
final class AppSession: ObservableObject {
    enum Surface: Equatable {
        case launching
        case signedOut
        case library
        case interior(capsuleID: UUID)
        case claim(capsuleID: UUID)
        case privateBlocked(capsuleID: UUID)
    }

    @Published var surface: Surface = .launching
    @Published var pendingTap: TapIntent?

    let auth: AuthService
    let api: CapsuleAPI
    let nfc: CapsuleNFCReader
    let router: TapRouter

    init(
        auth: AuthService = .shared,
        api: CapsuleAPI = .shared,
        nfc: CapsuleNFCReader = .shared
    ) {
        self.auth = auth
        self.api = api
        self.nfc = nfc
        self.router = TapRouter(api: api, auth: auth)
        Task { await bootstrap() }
    }

    func bootstrap() async {
        await auth.restore()
        if auth.user == nil {
            surface = .signedOut
        } else if let last = LastCapsule.read() {
            surface = .interior(capsuleID: last)
        } else {
            surface = .library
        }
    }

    func handleIncomingURL(_ url: URL) async {
        guard let id = TapIntent.parse(url) else { return }
        pendingTap = id
        await applyPendingTap()
    }

    func handleNFCRead(_ url: URL) async {
        await handleIncomingURL(url)
    }

    func applyPendingTap() async {
        guard let intent = pendingTap else { return }
        let outcome = await router.route(intent: intent)
        pendingTap = nil
        switch outcome {
        case .signInThenResume:
            surface = .signedOut
            pendingTap = intent
        case .claim(let id):
            surface = .claim(capsuleID: id)
        case .enter(let id):
            LastCapsule.write(id)
            surface = .interior(capsuleID: id)
        case .privateBlocked(let id):
            surface = .privateBlocked(capsuleID: id)
        case .notFound:
            surface = .library
        }
    }

    func didSignIn() async {
        await auth.refresh()
        if pendingTap != nil {
            await applyPendingTap()
        } else if let last = LastCapsule.read() {
            surface = .interior(capsuleID: last)
        } else {
            surface = .library
        }
    }

    func enter(capsule id: UUID) {
        LastCapsule.write(id)
        surface = .interior(capsuleID: id)
    }

    func openLibrary() {
        surface = .library
    }
}

private enum LastCapsule {
    private static let key = "capsule.lastOpened"
    static func read() -> UUID? {
        guard let s = UserDefaults.standard.string(forKey: key) else { return nil }
        return UUID(uuidString: s)
    }
    static func write(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: key)
    }
}
