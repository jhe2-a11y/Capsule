import SwiftUI

struct PrivateBlockedView: View {
    let capsuleID: UUID
    @EnvironmentObject private var session: AppSession
    @State private var requested = false
    @State private var working = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
                .frame(width: 120, height: 120)
                .overlay(
                    Image(systemName: "moon.stars")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.7))
                )

            Text("This Capsule is private.")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(.white.opacity(0.9))

            Text(requested
                 ? "We let the owner know."
                 : "You can ask the owner to share it.")
                .font(.system(.body, design: .serif).italic())
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Spacer()

            HStack(spacing: 16) {
                Button(action: { session.openLibrary() }) {
                    Text("Back")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white.opacity(0.04), in: Capsule())
                }
                Button(action: request) {
                    Text(requested ? "Sent" : (working ? "…" : "Request access"))
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white.opacity(0.92), in: Capsule())
                }
                .disabled(requested || working)
            }
            .padding(.horizontal, 28)

            Spacer().frame(height: 28)
        }
    }

    private func request() {
        guard !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                try await session.api.requestAccess(capsule: capsuleID, message: nil)
                requested = true
            } catch { }
        }
    }
}
