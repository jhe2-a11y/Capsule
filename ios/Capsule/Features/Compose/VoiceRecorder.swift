import SwiftUI
import AVFoundation

/// Tap-and-hold to record. Release commits, swipe-up to cancel. The waveform
/// pulses as the recording continues; on commit we upload and return.
struct VoiceRecorder: View {
    let capsuleID: UUID
    let onCommit: (Memory) -> Void

    @StateObject private var recorder = Recorder()
    @State private var holding = false
    @State private var dragOffset: CGSize = .zero
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Spacer()
            Text(holding ? "Recording…" : (working ? "Saving…" : "Hold to record"))
                .font(.system(.body, design: .serif))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 12)

            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 0.5)
                        .frame(width: 130 + CGFloat(i) * 28, height: 130 + CGFloat(i) * 28)
                        .scaleEffect(holding ? 1 + recorder.level * 0.4 : 1)
                        .animation(.easeOut(duration: 0.12), value: recorder.level)
                }
                Circle()
                    .fill(holding ? .red.opacity(0.7) : .white.opacity(0.06))
                    .frame(width: 100, height: 100)
                Image(systemName: "mic.fill")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white)
            }
            .scaleEffect(holding ? 1.05 : 1)
            .offset(dragOffset)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !holding && !working {
                            holding = true
                            recorder.start()
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        }
                        dragOffset = .init(width: 0, height: max(-100, v.translation.height))
                    }
                    .onEnded { v in
                        if v.translation.height < -60 {
                            recorder.cancel()
                            holding = false
                            dragOffset = .zero
                            return
                        }
                        finishRecording()
                    }
            )

            Spacer()
            Button(action: { dismiss() }) {
                Text("Cancel")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 28)
            }
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
    }

    private func finishRecording() {
        holding = false
        dragOffset = .zero
        guard let url = recorder.finish() else { return }
        working = true
        Task { @MainActor in
            do {
                let data = try Data(contentsOf: url)
                let id = UUID()
                let path = try await UploadPipeline.shared.upload(
                    capsuleID: capsuleID, memoryID: id, kind: .voice,
                    data: data, contentType: "audio/m4a")
                let memory = Memory(
                    id: id, capsuleID: capsuleID, kind: .voice,
                    storagePath: path, textContent: nil,
                    durationMs: Int(recorder.duration * 1000),
                    posX: Float.random(in: -0.5...0.5),
                    posY: Float.random(in: -0.5...0.5),
                    posZ: Float.random(in: 0.3...0.8),
                    createdAt: Date(),
                    createdBy: AuthService.shared.user?.id)
                onCommit(memory)
            } catch {
                // hold the modal so user can retry
            }
            working = false
        }
    }
}

@MainActor
private final class Recorder: ObservableObject {
    @Published var level: Float = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var url: URL?
    private(set) var duration: TimeInterval = 0
    private var startedAt: Date?

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let r = try AVAudioRecorder(url: dest, settings: settings)
            r.isMeteringEnabled = true
            r.record()
            self.recorder = r
            self.url = dest
            self.startedAt = Date()
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recorder?.updateMeters()
                    if let p = self?.recorder?.averagePower(forChannel: 0) {
                        let normalized = max(0, min(1, (p + 60) / 60))
                        self?.level = normalized
                    }
                }
            }
        } catch {
            self.recorder = nil
        }
    }

    func finish() -> URL? {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        if let s = startedAt { duration = Date().timeIntervalSince(s) }
        let result = url
        recorder = nil
        return result
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        if let url { try? FileManager.default.removeItem(at: url) }
        recorder = nil
        self.url = nil
    }
}
