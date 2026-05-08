import Foundation
import Metal
import MetalKit
import SwiftUI
import simd

// MARK: - GPU-side structs (mirror DepthField.metal)

struct DFVertex { var position: SIMD2<Float>; var uv: SIMD2<Float> }

struct DFInstance {
    var worldPos: SIMD3<Float>
    var sizePx:   SIMD2<Float>
    var rotation: Float
    var alpha:    Float
    var blur:     Float
    var focus:    Float
    var kindFlag: Float
    var _pad:     Float
}

struct DFCamera {
    var viewportSizePx: SIMD2<Float>
    var parallaxOffset: SIMD2<Float>
    var zoomZ:          Float
    var time:           Float
}

// MARK: - Per-node CPU-side state

final class DepthFieldNode {
    let memoryID: UUID
    var kind: MemoryKind
    var position: SIMD3<Float>
    var rotation: Float
    var sizePx: SIMD2<Float>
    var alpha: Float = 0
    var blur: Float = 1
    var focus: Float = 0
    var texture: MTLTexture?

    init(memoryID: UUID, kind: MemoryKind, position: SIMD3<Float>,
         rotation: Float = 0, sizePx: SIMD2<Float> = .init(180, 220)) {
        self.memoryID = memoryID
        self.kind = kind
        self.position = position
        self.rotation = rotation
        self.sizePx = sizePx
    }
}

// MARK: - Renderer

final class DepthFieldRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let vertexBuffer: MTLBuffer
    private let placeholderTexture: MTLTexture

    private(set) var nodes: [DepthFieldNode] = []
    private var instances: [DFInstance] = []
    private var instanceBuffer: MTLBuffer?

    var parallaxOffsetPx: SIMD2<Float> = .zero
    var cameraDolly: Float = 0
    private var startTime = CACurrentMediaTime()

    init?(device: MTLDevice) {
        guard
            let queue = device.makeCommandQueue(),
            let library = try? device.makeDefaultLibrary(bundle: .main),
            let vfn = library.makeFunction(name: "depthfield_vertex"),
            let ffn = library.makeFunction(name: "depthfield_fragment")
        else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: desc)
        else { return nil }

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear; sd.magFilter = .linear; sd.mipFilter = .linear
        sd.sAddressMode = .clampToEdge; sd.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: sd)
        else { return nil }

        let verts: [DFVertex] = [
            .init(position: .init(-0.5, -0.5), uv: .init(0, 1)),
            .init(position: .init( 0.5, -0.5), uv: .init(1, 1)),
            .init(position: .init(-0.5,  0.5), uv: .init(0, 0)),
            .init(position: .init( 0.5,  0.5), uv: .init(1, 0)),
        ]
        guard let vb = device.makeBuffer(
            bytes: verts,
            length: MemoryLayout<DFVertex>.stride * verts.count,
            options: .storageModeShared)
        else { return nil }

        let placeholder = Self.makeSolidTexture(device: device, color: .init(0.92, 0.88, 0.82, 1.0))

        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.sampler = sampler
        self.vertexBuffer = vb
        self.placeholderTexture = placeholder
        super.init()
    }

    // MARK: node management

    func setNodes(_ memories: [Memory]) {
        // Reuse existing nodes by memoryID; new ones materialize from alpha=0.
        var byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.memoryID, $0) })
        var next: [DepthFieldNode] = []
        for m in memories {
            if let existing = byID.removeValue(forKey: m.id) {
                existing.position = m.position
                existing.kind = m.kind
                next.append(existing)
            } else {
                next.append(DepthFieldNode(
                    memoryID: m.id, kind: m.kind, position: m.position,
                    rotation: Float.random(in: -0.05...0.05),
                    sizePx: defaultSize(for: m.kind)))
            }
        }
        nodes = next
    }

    func upsertNode(_ memory: Memory) {
        if let existing = nodes.first(where: { $0.memoryID == memory.id }) {
            existing.position = memory.position
            existing.kind = memory.kind
            return
        }
        nodes.append(DepthFieldNode(
            memoryID: memory.id, kind: memory.kind, position: memory.position,
            rotation: Float.random(in: -0.05...0.05),
            sizePx: defaultSize(for: memory.kind)))
    }

    func removeNode(id: UUID) {
        nodes.removeAll { $0.memoryID == id }
    }

    func setTexture(_ tex: MTLTexture, for memoryID: UUID) {
        nodes.first(where: { $0.memoryID == memoryID })?.texture = tex
    }

    func setFocus(_ focusedID: UUID?) {
        for n in nodes {
            n.focus = (n.memoryID == focusedID) ? 1.0 : 0.0
        }
    }

    func node(at point: CGPoint, in size: CGSize) -> DepthFieldNode? {
        // Hit test in screen px; iterate front-to-back (largest scale first).
        let vp = SIMD2<Float>(Float(size.width), Float(size.height))
        let ordered = nodes.sorted { ($0.position.z + cameraDolly) > ($1.position.z + cameraDolly) }
        for n in ordered {
            let z = max(0, min(0.99, n.position.z + cameraDolly))
            let depth = 1.2 - z
            let scale = 1.0 / depth
            let centerPx = SIMD2<Float>(
                Float(n.position.x) * vp.x * 0.5 + parallaxOffsetPx.x * mix(0.4, 1.0, z),
                Float(n.position.y) * vp.y * 0.5 + parallaxOffsetPx.y * mix(0.4, 1.0, z))
            let half = n.sizePx * scale * 0.5
            let p = SIMD2<Float>(Float(point.x) - vp.x * 0.5,
                                 Float(point.y) - vp.y * 0.5)
            // Note: the renderer maps y so that +y is up (NDC is flipped); the
            // hit test mirrors the same convention.
            let dx = p.x - centerPx.x
            let dy = -p.y - centerPx.y
            if abs(dx) <= half.x && abs(dy) <= half.y {
                return n
            }
        }
        return nil
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let cmd = queue.makeCommandBuffer(),
            let enc = cmd.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        // Animate per-node alpha/blur toward target (materialize-load).
        let dt: Float = 1.0 / Float(view.preferredFramesPerSecond > 0 ? view.preferredFramesPerSecond : 60)
        for n in nodes {
            n.alpha = approach(n.alpha, target: n.texture == nil ? 0.35 : 1.0, rate: 1.6 * dt)
            n.blur  = approach(n.blur,  target: n.texture == nil ? 1.0 : 0.0,  rate: 1.6 * dt)
        }

        // Build instance list, sorted back-to-front for correct alpha blending.
        let sorted = nodes.sorted { ($0.position.z + cameraDolly) < ($1.position.z + cameraDolly) }
        instances.removeAll(keepingCapacity: true)
        instances.reserveCapacity(sorted.count)
        for n in sorted {
            instances.append(.init(
                worldPos: n.position,
                sizePx: n.sizePx,
                rotation: n.rotation,
                alpha: n.alpha,
                blur: n.blur,
                focus: n.focus,
                kindFlag: kindFlag(n.kind),
                _pad: 0))
        }

        let bufLen = MemoryLayout<DFInstance>.stride * max(instances.count, 1)
        if (instanceBuffer?.length ?? 0) < bufLen {
            instanceBuffer = device.makeBuffer(length: bufLen, options: .storageModeShared)
        }
        if let ib = instanceBuffer, !instances.isEmpty {
            ib.contents().copyMemory(
                from: instances, byteCount: MemoryLayout<DFInstance>.stride * instances.count)
        }

        let drawableSize = view.drawableSize
        var camera = DFCamera(
            viewportSizePx: .init(Float(drawableSize.width), Float(drawableSize.height)),
            parallaxOffset: parallaxOffsetPx * Float(view.contentScaleFactor),
            zoomZ: cameraDolly,
            time: Float(CACurrentMediaTime() - startTime))

        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        if let ib = instanceBuffer {
            enc.setVertexBuffer(ib, offset: 0, index: 1)
        }
        enc.setVertexBytes(&camera, length: MemoryLayout<DFCamera>.stride, index: 2)
        enc.setFragmentSamplerState(sampler, index: 0)

        // Draw each node separately so we can swap textures per instance.
        for (i, node) in sorted.enumerated() {
            enc.setFragmentTexture(node.texture ?? placeholderTexture, index: 0)
            enc.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: 1,
                baseInstance: i)
        }
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: helpers

    private func defaultSize(for kind: MemoryKind) -> SIMD2<Float> {
        switch kind {
        case .photo: return .init(220, 280)
        case .video: return .init(240, 280)
        case .voice: return .init(160, 160)
        case .text:  return .init(220, 280)
        }
    }

    private func kindFlag(_ kind: MemoryKind) -> Float {
        switch kind {
        case .photo: return 0
        case .video: return 1
        case .voice: return 2
        case .text:  return 3
        }
    }

    private static func makeSolidTexture(device: MTLDevice, color: SIMD4<Float>) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        desc.usage = [.shaderRead]
        let tex = device.makeTexture(descriptor: desc)!
        var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
        let r = UInt8(clamping: Int(color.x * 255))
        let g = UInt8(clamping: Int(color.y * 255))
        let b = UInt8(clamping: Int(color.z * 255))
        let a = UInt8(clamping: Int(color.w * 255))
        var i = 0
        while i < pixels.count {
            pixels[i + 0] = b
            pixels[i + 1] = g
            pixels[i + 2] = r
            pixels[i + 3] = a
            i += 4
        }
        pixels.withUnsafeBytes {
            tex.replace(
                region: MTLRegionMake2D(0, 0, 4, 4),
                mipmapLevel: 0,
                withBytes: $0.baseAddress!,
                bytesPerRow: 16)
        }
        return tex
    }
}

private func approach(_ value: Float, target: Float, rate: Float) -> Float {
    if abs(target - value) < 0.001 { return target }
    return value + (target - value) * min(1, rate)
}

private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
