import SwiftUI

@main
struct CapsuleApp: App {
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        Task { await session.handleIncomingURL(url) }
                    }
                }
                .onOpenURL { url in
                    Task { await session.handleIncomingURL(url) }
                }
        }
    }
}
