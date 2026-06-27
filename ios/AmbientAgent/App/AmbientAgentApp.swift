import SwiftUI

@main
struct AmbientAgentApp: App {
    // One session object for the whole app — the on-device conversation loop.
    @State private var session = ConversationSession()
    @State private var watchLink: WatchLink?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .task {
                    // The watch button calls the same wake() the on-screen button does.
                    if watchLink == nil {
                        watchLink = WatchLink(onWake: { [session] in
                            Task { await session.wake() }
                        })
                    }
                }
        }
    }
}
