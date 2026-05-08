import Foundation
import AuthenticationServices
import CryptoKit
import Supabase
import UIKit

/// Sign in with Apple → Supabase. Surface area kept tiny on purpose: every
/// extra auth step is a moment where the technology becomes visible.
@MainActor
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    @Published private(set) var user: User?

    private let client = SupabaseClientFactory.shared
    private var currentNonce: String?
    private var currentContinuation: CheckedContinuation<User, Error>?

    func restore() async {
        do {
            let session = try await client.auth.session
            user = session.user
        } catch {
            user = nil
        }
    }

    func refresh() async {
        await restore()
    }

    func signOut() async {
        try? await client.auth.signOut()
        user = nil
    }

    /// Begins Sign in with Apple. Returns when Supabase has a session.
    func signInWithApple() async throws -> User {
        let nonce = Nonce.make()
        currentNonce = nonce
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Nonce.sha256(nonce)

        return try await withCheckedThrowingContinuation { cont in
            self.currentContinuation = cont
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension AuthService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            currentContinuation?.resume(throwing: AuthError.missingToken)
            currentContinuation = nil
            return
        }

        let cont = currentContinuation
        currentContinuation = nil
        Task { [client] in
            do {
                let session = try await client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
                await MainActor.run { self.user = session.user }
                cont?.resume(returning: session.user)
            } catch {
                cont?.resume(throwing: error)
            }
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        currentContinuation?.resume(throwing: error)
        currentContinuation = nil
    }
}

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

enum AuthError: Error { case missingToken }

private enum Nonce {
    static func make(length: Int = 32) -> String {
        let chars: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var out = ""
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        for b in bytes { out.append(chars[Int(b) % chars.count]) }
        return out
    }
    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
