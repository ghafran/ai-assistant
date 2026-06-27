import SwiftUI

/// The whole watch app: one big button that wakes the phone to listen.
struct WatchContentView: View {
    @StateObject private var connector = WatchConnector()

    var body: some View {
        VStack(spacing: 10) {
            Button {
                connector.sendWake()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 34))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            Text(connector.lastSentAt == nil ? "Tap to wake" : "Listening on phone…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
