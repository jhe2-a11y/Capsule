import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ZStack {
            BackgroundField()
                .ignoresSafeArea()

            switch session.surface {
            case .launching:
                LaunchAmbient()
            case .signedOut:
                SignInView()
            case .library:
                LibraryView()
            case .interior(let id):
                InteriorView(capsuleID: id)
                    .id(id)
                    .transition(.opacity)
            case .claim(let id):
                ClaimSheet(capsuleID: id)
            case .privateBlocked(let id):
                PrivateBlockedView(capsuleID: id)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: session.surface)
    }
}

private struct LaunchAmbient: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: [.white.opacity(0.18), .clear],
                center: .center, startRadius: 0, endRadius: 220))
            .frame(width: 440, height: 440)
            .blur(radius: 60)
            .scaleEffect(0.9 + phase * 0.1)
            .opacity(0.6 + phase * 0.4)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever()) {
                    phase = 1
                }
            }
    }
}

private struct BackgroundField: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.06),
                         Color(red: 0.10, green: 0.07, blue: 0.12)],
                startPoint: .top, endPoint: .bottom)
            Color.black.opacity(0.2)
                .blendMode(.multiply)
        }
    }
}
