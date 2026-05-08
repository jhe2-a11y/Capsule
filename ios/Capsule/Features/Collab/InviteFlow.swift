import SwiftUI
import UIKit

struct CapsuleSettingsView: View {
    let capsuleID: UUID
    @EnvironmentObject private var session: AppSession
    @State private var capsule: Capsule?
    @State private var inviteURL: URL?
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                if let capsule {
                    Toggle("Private", isOn: Binding(
                        get: { capsule.accessMode == .private },
                        set: { newValue in
                            self.capsule?.accessMode = newValue ? .private : .open
                            Task {
                                try? await session.api.setAccessMode(
                                    capsule: capsuleID,
                                    mode: newValue ? .private : .open)
                            }
                        }
                    ))
                    .tint(.white)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.white.opacity(0.9))

                    Button(action: makeInvite) {
                        Text(inviteURL == nil ? "Create invite link" : "Copy invite link")
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(.white.opacity(0.06), in: Capsule())
                    }
                    .disabled(working)

                    if let inviteURL {
                        Text(inviteURL.absoluteString)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    ProgressView().tint(.white)
                }

                Spacer()
            }
            .padding(28)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Capsule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .task {
            capsule = try? await session.api.fetchCapsule(id: capsuleID)
        }
    }

    private func makeInvite() {
        if let inviteURL {
            UIPasteboard.general.url = inviteURL
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        working = true
        Task {
            defer { working = false }
            do {
                let token = try await session.api.createInvite(capsule: capsuleID)
                let url = URL(string: "https://\(AppConfig.universalLinkHost)/c/\(capsuleID)?invite=\(token)")
                self.inviteURL = url
            } catch {
                self.inviteURL = nil
            }
        }
    }
}
