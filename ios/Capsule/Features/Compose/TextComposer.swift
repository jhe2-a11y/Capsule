import SwiftUI

struct TextComposer: View {
    let capsuleID: UUID
    let onCommit: (Memory) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Button(action: commit) {
                        Text("Done")
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                             ? .white.opacity(0.3) : .white.opacity(0.95))
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .font(.system(.title3, design: .serif))
                    .lineSpacing(8)
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 24)
                    .focused($focused)
                    .onAppear { focused = true }
            }
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let memory = Memory(
            id: UUID(),
            capsuleID: capsuleID,
            kind: .text,
            storagePath: nil,
            textContent: trimmed,
            durationMs: nil,
            posX: Float.random(in: -0.5...0.5),
            posY: Float.random(in: -0.5...0.5),
            posZ: Float.random(in: 0.3...0.8),
            createdAt: Date(),
            createdBy: AuthService.shared.user?.id)
        onCommit(memory)
    }
}
