import Foundation
import UIKit
import AVFoundation

/// Renders an audio file's waveform into a soft, glowing image. Used as the
/// node texture for `voice` memories so the field shows breathing waveforms
/// rather than a generic mic icon.
enum WaveformRenderer {
    static func image(for data: Data, size: CGSize) -> UIImage? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")
        try? data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let samples = (try? readSamples(from: tmp, downsampleTo: 96)) ?? []
        return drawWaveform(samples: samples, size: size)
    }

    private static func drawWaveform(samples: [Float], size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.clear.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            cg.setStrokeColor(UIColor(white: 1.0, alpha: 0.85).cgColor)
            cg.setLineWidth(1.4)
            cg.setLineCap(.round)

            let mid = size.height / 2
            let count = max(samples.count, 1)
            let step = size.width / CGFloat(count)
            for (i, s) in samples.enumerated() {
                let h = CGFloat(s) * mid * 0.85 + 1
                let x = CGFloat(i) * step + step * 0.5
                cg.move(to: .init(x: x, y: mid - h))
                cg.addLine(to: .init(x: x, y: mid + h))
            }
            cg.strokePath()
        }
    }

    private static func readSamples(from url: URL, downsampleTo bins: Int) throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        reader.startReading()

        var allMagnitudes: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { ptr in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                               destination: ptr.baseAddress!)
            }
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let int16 = raw.bindMemory(to: Int16.self)
                for s in int16 {
                    allMagnitudes.append(abs(Float(s)) / Float(Int16.max))
                }
            }
        }

        guard !allMagnitudes.isEmpty else { return [] }
        let bin = max(1, allMagnitudes.count / bins)
        var out: [Float] = []
        out.reserveCapacity(bins)
        var i = 0
        while i < allMagnitudes.count {
            let end = min(i + bin, allMagnitudes.count)
            var sum: Float = 0
            for j in i..<end { sum += allMagnitudes[j] }
            out.append(sum / Float(end - i))
            i = end
        }
        // Normalize.
        if let mx = out.max(), mx > 0 {
            for k in 0..<out.count { out[k] /= mx }
        }
        return out
    }
}
