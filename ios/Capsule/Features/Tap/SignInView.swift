import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject private var session: AppSession
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 36) {
            Spacer()

            // A single soft mark — the only image in the sign-in screen.
            Circle()
                .fill(.white.opacity(0.04))
                .frame(width: 84, height: 84)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                )

            Text("Capsule")
                .font(.system(.title2, design: .serif))
                .foregroundStyle(.white.opacity(0.92))
                .tracking(2)

            Spacer()

            SignInWithAppleButton(.continue, onRequest: { _ in }, onCompletion: { _ in })
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .padding(.horizontal, 32)
                .allowsHitTesting(false)
                .overlay(
                    Button(action: tapSignIn) { Color.clear }
                        .padding(.horizontal, 32)
                        .frame(height: 52)
                )

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer().frame(height: 28)
        }
        .opacity(working ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.4), value: working)
    }

    private func tapSignIn() {
        guard !working else { return }
        working = true
        error = nil
        Task {
            do {
                _ = try await session.auth.signInWithApple()
                await session.didSignIn()
            } catch {
                self.error = "Sign in didn’t complete. Try again."
            }
            working = false
        }
    }
}
