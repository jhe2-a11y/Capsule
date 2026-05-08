import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PhotoVideoPicker: UIViewControllerRepresentable {
    let kind: MemoryKind
    let capsuleID: UUID
    let onCommit: (Memory) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = (kind == .photo) ? .images : .videos
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(kind: kind, capsuleID: capsuleID, onCommit: onCommit)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let kind: MemoryKind
        let capsuleID: UUID
        let onCommit: (Memory) -> Void

        init(kind: MemoryKind, capsuleID: UUID, onCommit: @escaping (Memory) -> Void) {
            self.kind = kind
            self.capsuleID = capsuleID
            self.onCommit = onCommit
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                picker.dismiss(animated: true)
                return
            }
            let provider = result.itemProvider
            let memoryID = UUID()

            Task { @MainActor in
                do {
                    let (data, contentType) = try await Self.load(provider: provider, kind: kind)
                    let path = try await UploadPipeline.shared.upload(
                        capsuleID: capsuleID,
                        memoryID: memoryID,
                        kind: kind,
                        data: data,
                        contentType: contentType)
                    let memory = Memory(
                        id: memoryID,
                        capsuleID: capsuleID,
                        kind: kind,
                        storagePath: path,
                        textContent: nil,
                        durationMs: nil,
                        posX: Float.random(in: -0.5...0.5),
                        posY: Float.random(in: -0.5...0.5),
                        posZ: Float.random(in: 0.3...0.8),
                        createdAt: Date(),
                        createdBy: AuthService.shared.user?.id)
                    onCommit(memory)
                } catch {
                    // Composer keeps the modal up on hard failure.
                }
                picker.dismiss(animated: true)
            }
        }

        private static func load(provider: NSItemProvider, kind: MemoryKind) async throws -> (Data, String) {
            switch kind {
            case .photo:
                if provider.canLoadObject(ofClass: UIImage.self) {
                    let image: UIImage = try await withCheckedThrowingContinuation { cont in
                        provider.loadObject(ofClass: UIImage.self) { obj, err in
                            if let img = obj as? UIImage { cont.resume(returning: img) }
                            else { cont.resume(throwing: err ?? URLError(.badServerResponse)) }
                        }
                    }
                    let resized = image.fitting(maxDimension: 2048)
                    guard let data = resized.jpegData(compressionQuality: 0.86) else {
                        throw URLError(.cannotDecodeContentData)
                    }
                    return (data, "image/jpeg")
                }
                throw URLError(.unsupportedURL)
            case .video:
                let url: URL = try await withCheckedThrowingContinuation { cont in
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, err in
                        if let url {
                            // Copy to a stable location; the system url is ephemeral.
                            let dest = FileManager.default.temporaryDirectory
                                .appendingPathComponent(UUID().uuidString + ".mp4")
                            try? FileManager.default.copyItem(at: url, to: dest)
                            cont.resume(returning: dest)
                        } else {
                            cont.resume(throwing: err ?? URLError(.badServerResponse))
                        }
                    }
                }
                let data = try Data(contentsOf: url)
                return (data, "video/mp4")
            default:
                throw URLError(.unsupportedURL)
            }
        }
    }
}

private extension UIImage {
    func fitting(maxDimension: CGFloat) -> UIImage {
        let m = max(size.width, size.height)
        guard m > maxDimension else { return self }
        let scale = maxDimension / m
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
