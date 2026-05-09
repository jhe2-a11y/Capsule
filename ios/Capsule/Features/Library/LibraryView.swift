import SwiftUI

/// The user's owned + collaborator capsules, rendered as a small constellation
/// (no list, no grid). Tap a node to enter its interior.
struct LibraryView: View {
    @EnvironmentObject private var session: AppSession
    @State private var capsules: [Capsule] = []
    @State private var positions: [UUID: CGPoint] = [:]
    @State private var loading = true
    @State private var nfcRunning = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(capsules) { capsule in
                    LibraryNode(capsule: capsule)
                        .position(positions[capsule.id] ?? geo.size.midpoint)
                        .onTapGesture { session.enter(capsule: capsule.id) }
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }

                VStack {
                    Spacer()
                    HStack(spacing: 28) {
                        Button(action: tap) {
                            Label("Tap a Capsule", systemImage: "wave.3.right")
                                .font(.system(.body, design: .serif))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: SwiftUI.Capsule())
                        }

                        Button(action: signOut) {
                            Image(systemName: "person.circle")
                                .foregroundStyle(.white.opacity(0.5))
                                .font(.system(size: 22, weight: .light))
                        }
                    }
                    .padding(.bottom, 28)
                }

                if loading && capsules.isEmpty {
                    Text("…")
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.white.opacity(0.35))
                }

                if !loading && capsules.isEmpty {
                    VStack(spacing: 8) {
                        Text("No Capsules yet.")
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Tap one to begin.")
                            .font(.system(.footnote, design: .serif))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .task { await load(in: geo.size) }
        }
    }

    private func load(in size: CGSize) async {
        do {
            capsules = try await session.api.myCapsules()
            positions = scatter(capsules.map(\.id), in: size)
            loading = false
        } catch {
            loading = false
        }
    }

    private func scatter(_ ids: [UUID], in size: CGSize) -> [UUID: CGPoint] {
        guard !ids.isEmpty else { return [:] }
        var result: [UUID: CGPoint] = [:]
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.32
        for (i, id) in ids.enumerated() {
            let angle = (Double(i) / Double(ids.count)) * .pi * 2 + .pi / 6
            let r = radius * (0.55 + Double(i % 3) * 0.18)
            result[id] = CGPoint(
                x: center.x + CGFloat(cos(angle)) * r,
                y: center.y + CGFloat(sin(angle)) * r)
        }
        return result
    }

    private func tap() {
        guard !nfcRunning else { return }
        nfcRunning = true
        Task {
            defer { nfcRunning = false }
            do {
                let url = try await session.nfc.read()
                await session.handleNFCRead(url)
            } catch { }
        }
    }

    private func signOut() {
        Task {
            await session.auth.signOut()
            await session.bootstrap()
        }
    }
}

private struct LibraryNode: View {
    let capsule: Capsule
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 96, height: 96)
                .blur(radius: 18)
                .scaleEffect(0.95 + phase * 0.08)
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
                .frame(width: 64, height: 64)
            if let title = capsule.title, !title.isEmpty {
                Text(title)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: 56)
                    .frame(width: 140)
                    .multilineTextAlignment(.center)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: Double.random(in: 2.4...3.6))
                .repeatForever()) { phase = 1 }
        }
    }
}

private extension CGSize {
    var midpoint: CGPoint { .init(x: width / 2, y: height / 2) }
}
