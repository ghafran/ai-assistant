import SwiftUI

/// Minimal interface: a big wake button (stands in for the physical BLE button),
/// the live transcript, and the resulting TaskSpec. The app is just an I/O surface
/// for the conversation loop — all the work happens in `ConversationSession`.
struct ContentView: View {
    @Environment(ConversationSession.self) private var session

    var body: some View {
        VStack(spacing: 24) {
            statusHeader

            Spacer()

            // Live transcript / model output
            ScrollView {
                Text(session.displayText.isEmpty ? "Tap the button and speak." : session.displayText)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(session.displayText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 220)

            if let spec = session.lastTaskSpec {
                TaskSpecCard(spec: spec)
            }

            Spacer()

            wakeButton
        }
        .padding(28)
        .task { await session.prepare() }
        .sheet(isPresented: Binding(
            get: { session.pendingCompose != nil },
            set: { if !$0 { session.dismissCompose() } }
        )) {
            if let compose = session.pendingCompose {
                MessageComposer(
                    recipients: [compose.toPhone],
                    body: compose.body,
                    onFinish: { session.dismissCompose() }
                )
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.phase.tint)
                .frame(width: 10, height: 10)
            Text(session.phase.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var wakeButton: some View {
        Button {
            Task {
                if session.phase == .listening {
                    await session.finishAndProcess()
                } else {
                    await session.wake()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(session.phase == .listening ? Color.red : Color.accentColor)
                    .frame(width: 120, height: 120)
                    .shadow(radius: session.phase == .listening ? 12 : 4)
                Image(systemName: session.phase == .listening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }
        }
        .disabled(session.phase == .thinking || session.phase == .speaking)
        .animation(.spring(duration: 0.25), value: session.phase)
    }
}

private struct TaskSpecCard: View {
    let spec: TaskSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(spec.intent.rawValue, systemImage: "bolt.fill")
                .font(.headline)
            Text(spec.summary).font(.subheadline)
            if spec.needsClarification, !spec.clarifyingQuestion.isEmpty {
                Text("❓ \(spec.clarifyingQuestion)")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }
}
