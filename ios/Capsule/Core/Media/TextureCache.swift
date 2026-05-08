import AVFoundation
import Foundation
import Metal
import MetalKit
import UIKit

/// Loads memory media (photo first frames, video posters, voice waveforms)
/// into Metal textures. In-memory LRU keyed by memory ID.
@MainActor
final class TextureCache {
    static let shared = TextureCache()
    private let device = MTLCreateSystemDefaultDevice()!
    private lazy var loader = MTKTextureLoader(device: device)
    private var cache: [UUID: MTLTexture] = [:]
    private var inflight: Set<UUID> = []

    func texture(for memory: Memory, url: URL?) async -> MTLTexture? {
        if let cached = cache[memory.id] { return cached }
        guard let url, !inflight.contains(memory.id) else { return nil }
        inflight.insert(memory.id)
        defer { inflight.remove(memory.id) }

        do {
            let data = try await Self.fetch(url: url)
            let image: UIImage?
            switch memory.kind {
            case .photo:
                image = UIImage(data: data)
            case .video:
                image = await Self.posterFrame(from: data)
            case .voice:
                image = WaveformRenderer.image(for: data, size: CGSize(width: 256, height: 256))
            case .text:
                image = nil
            }
            guard let cg = image?.cgImage else { return nil }
            let tex = try loader.newTexture(cgImage: cg, options: [
                .SRGB: false,
                .generateMipmaps: true,
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            ])
            cache[memory.id] = tex
            return tex
        } catch {
            return nil
        }
    }

    private static func fetch(url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    private static func posterFrame(from videoData: Data) async -> UIImage? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        try? videoData.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let asset = AVURLAsset(url: tmp)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        do {
            let cg = try await gen.image(at: .zero).image
            return UIImage(cgImage: cg)
        } catch {
            return nil
        }
    }
}
