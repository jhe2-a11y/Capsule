import SwiftUI
import UIKit

struct CapsuleSettingsView: View {
    let capsuleID: UUID
    @EnvironmentObject private var session: AppSession
    @State private var capsule: Capsule?
    @State private var inviteURL: URL?
    @State private var working = false
    @State private var encodeStatus: EncodeStatus = .idle
    @Environment(\.dismiss) private var dismiss

    enum EncodeStatus: Equatable {
        case idle, working, succeeded, failed(String)
    }

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
                            .background(.white.opacity(0.06), in: SwiftUI.Capsule())
                    }
                    .disabled(working)

                    if let inviteURL {
                        Text(inviteURL.absoluteString)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Spacer()

                    // Re-encode chip — shown only after a deliberate long-press
                    // on the title so it stays out of the everyday surface.
                    encodePanel
                } else {
                    ProgressView().tint(.white)
                    Spacer()
                }
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

    /// Hidden re-encode affordance: the user must long-press the soft mark
    /// to reveal it. Keeps the everyday surface free of "technology".
    @ViewBuilder
    private var encodePanel: some View {
        VStack(spacing: 12) {
            SwiftUI.Capsule()
                .fill(.white.opacity(0.05))
                .frame(width: 64, height: 4)
                .gesture(
                    LongPressGesture(minimumDuration: 1.2)
                        .onEnded { _ in reEncode() }
                )

            switch encodeStatus {
            case .idle:
                EmptyView()
            case .working:
                Text("Hold a chip to the top of your phone…")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(.white.opacity(0.55))
            case .succeeded:
                Text("Encoded.")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(.white.opacity(0.7))
            case .failed(let msg):
                Text(msg)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 12)
    }

    private func reEncode() {
        let url = URL(string: "https://\(AppConfig.universalLinkHost)/c/\(capsuleID)")
        guard let url else { return }
        encodeStatus = .working
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        Task {
            do {
                try await CapsuleNFCWriter.shared.write(url: url)
                encodeStatus = .succeeded
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch CapsuleNFCWriter.WriteError.unavailable {
                encodeStatus = .failed("This phone can’t encode chips.")
            } catch CapsuleNFCWriter.WriteError.readOnly {
                encodeStatus = .failed("This chip can’t be rewritten.")
            } catch {
                encodeStatus = .failed("Encoding didn’t complete.")
            }
        }
    }
}
