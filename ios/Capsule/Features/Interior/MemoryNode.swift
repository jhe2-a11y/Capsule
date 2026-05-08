import SwiftUI
import AVKit

/// SwiftUI overlay layer per memory. The Metal renderer paints the field;
/// these views render the *foregrounded* node (text composition, video
/// playback) and act as accessibility surfaces.
struct ForegroundedMemoryView: View {
    let memory: Memory
    let mediaURL: URL?

    var body: some View {
        Group {
            switch memory.kind {
            case .text:  textView
            case .photo: photoView
            case .video: videoView
            case .voice: voiceView
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private var textView: some View {
        ScrollView {
            Text(memory.textContent ?? "")
                .font(.system(.title3, design: .serif))
                .lineSpacing(8)
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 28)
                .padding(.vertical, 56)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var photoView: some View {
        if let url = mediaURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit().kenBurns()
                default:
                    Rectangle().fill(.white.opacity(0.04))
                }
            }
        } else {
            Rectangle().fill(.white.opacity(0.04))
        }
    }

    @ViewBuilder
    private var videoView: some View {
        if let url = mediaURL {
            VideoLooper(url: url)
        } else {
            Rectangle().fill(.white.opacity(0.04))
        }
    }

    private var voiceView: some View {
        VoicePlayerView(url: mediaURL)
    }
}

private struct VideoLooper: View {
    let url: URL
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.isMuted = true; player.play() }
                    .onDisappear { player.pause() }
            } else {
                Color.clear
            }
        }
        .onAppear {
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer(playerItem: item)
            self.looper = AVPlayerLooper(player: queue, templateItem: item)
            self.player = queue
        }
    }
}

private struct VoicePlayerView: View {
    let url: URL?
    @StateObject private var player = VoicePlayer()
    @State private var phase: CGFloat = 0

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 0.5)
                        .frame(width: 140 + CGFloat(i) * 30, height: 140 + CGFloat(i) * 30)
                        .scaleEffect(player.isPlaying ? (1 + 0.05 * sin(phase + CGFloat(i))) : 1)
                }
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 100, height: 100)
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .onTapGesture {
                if let url { player.toggle(url: url) }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
        .onDisappear { player.stop() }
    }
}

@MainActor
private final class VoicePlayer: ObservableObject {
    @Published var isPlaying = false
    private var player: AVPlayer?

    func toggle(url: URL) {
        if isPlaying { stop() }
        else {
            let p = AVPlayer(url: url)
            p.play()
            self.player = p
            isPlaying = true
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: p.currentItem, queue: .main
            ) { [weak self] _ in self?.stop() }
        }
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
    }
}

private extension Image {
    func kenBurns() -> some View {
        modifier(KenBurnsModifier())
    }
}

private struct KenBurnsModifier: ViewModifier {
    @State private var t: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .scaleEffect(1.04 + 0.04 * t)
            .offset(x: 6 * t, y: -4 * t)
            .onAppear {
                withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                    t = 1
                }
            }
    }
}
