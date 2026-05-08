import SwiftUI

/// Modal entry point — routes to the kind-specific composer. Each composer
/// returns a fully-formed `Memory` (with storage_path already uploaded).
struct MemoryComposer: View {
    let kind: MemoryKind
    let capsuleID: UUID
    let onCommit: (Memory) -> Void

    var body: some View {
        Group {
            switch kind {
            case .photo: PhotoVideoPicker(kind: .photo, capsuleID: capsuleID, onCommit: onCommit)
            case .video: PhotoVideoPicker(kind: .video, capsuleID: capsuleID, onCommit: onCommit)
            case .voice: VoiceRecorder(capsuleID: capsuleID, onCommit: onCommit)
            case .text:  TextComposer(capsuleID: capsuleID, onCommit: onCommit)
            }
        }
        .preferredColorScheme(.dark)
    }
}
