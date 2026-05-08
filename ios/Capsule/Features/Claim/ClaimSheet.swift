import SwiftUI

struct ClaimSheet: View {
    let capsuleID: UUID
    @EnvironmentObject private var session: AppSession
    @State private var working = false
    @State private var error: String?
    @State private var phase: CGFloat = 0

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 220, height: 220)
                    .blur(radius: 30)
                    .scaleEffect(0.95 + phase * 0.1)
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
                    .frame(width: 160, height: 160)
            }

            Text("This Capsule is unclaimed.")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)

            Text("Make it yours?")
                .font(.system(.body, design: .serif).italic())
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            HStack(spacing: 16) {
                Button(action: decline) {
                    Text("Not now")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white.opacity(0.04), in: Capsule())
                }
                Button(action: claim) {
                    Text(working ? "Opening…" : "Yes")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white.opacity(0.92), in: Capsule())
                }
                .disabled(working)
            }
            .padding(.horizontal, 28)

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer().frame(height: 28)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever()) {
                phase = 1
            }
        }
    }

    private func claim() {
        guard !working else { return }
        working = true
        error = nil
        Task {
            do {
                let c = try await session.api.claim(capsule: capsuleID)
                session.enter(capsule: c.id)
            } catch {
                self.error = "Couldn’t claim this Capsule."
            }
            working = false
        }
    }

    private func decline() {
        session.openLibrary()
    }
}
