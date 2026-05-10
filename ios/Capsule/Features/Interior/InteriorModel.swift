import Foundation
import Metal
import simd

@MainActor
final class InteriorModel: ObservableObject {
    @Published var capsule: Capsule?
    @Published var memories: [Memory] = []
    @Published var canEdit = false
    @Published var focus = FocusController()
    @Published var pendingUploads: Set<UUID> = []

    let renderer: DepthFieldRenderer?
    private var motion = ParallaxMotion()
    private var realtime: CapsuleRealtimeChannel?
    private var api: CapsuleAPI?
    private var auth: AuthService?

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            renderer = DepthFieldRenderer(device: device)
        } else {
            renderer = nil
        }
    }

    var focusedMemory: Memory? {
        guard let id = focus.focusedMemoryID else { return nil }
        return memories.first(where: { $0.id == id })
    }

    func start(capsuleID: UUID, api: CapsuleAPI, auth: AuthService) async {
        self.api = api
        self.auth = auth

        motion.start()
        Task { @MainActor [weak self] in
            // Drive parallax → renderer every frame.
            while let self {
                self.renderer?.parallaxOffsetPx = self.motion.offsetPx
                self.renderer?.cameraDolly = self.focus.dolly
                self.renderer?.setFocus(self.focus.focusedMemoryID)
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }

        do {
            self.capsule = try await api.fetchCapsule(id: capsuleID)
            self.canEdit = (capsule?.ownerID == auth.user?.id)
            let mems = try await api.fetchMemories(capsule: capsuleID)
            applyMemories(mems)
            await loadTextures(for: mems)
        } catch {
            // The renderer keeps running with no memories; the field remains
            // present rather than blocking on data.
        }

        let channel = CapsuleRealtimeChannel(capsule: capsuleID) { [weak self] event in
            Task { @MainActor [weak self] in self?.handleRealtime(event) }
        }
        await channel.start()
        self.realtime = channel
    }

    func stop() async {
        motion.stop()
        await realtime?.stop()
        realtime = nil
    }

    private func handleRealtime(_ event: CapsuleRealtimeChannel.Event) {
        switch event {
        case .memoryInserted(let m):
            if !memories.contains(where: { $0.id == m.id }) {
                memories.append(m)
                renderer?.upsertNode(m)
                Task { await loadTexture(for: m) }
            }
        case .memoryUpdated(let m):
            if let idx = memories.firstIndex(where: { $0.id == m.id }) {
                memories[idx] = m
                renderer?.upsertNode(m)
            }
        case .memoryDeleted(let id):
            memories.removeAll { $0.id == id }
            renderer?.removeNode(id: id)
        case .capsuleUpdated(let c):
            self.capsule = c
            self.canEdit = (c.ownerID == auth?.user?.id)
        }
    }

    func didCompose(_ memory: Memory) async {
        // Optimistic insert: the composer has already returned a placeholder
        // memory; here we run the upload + DB insert.
        memories.append(memory)
        renderer?.upsertNode(memory)
        pendingUploads.insert(memory.id)
        defer { pendingUploads.remove(memory.id) }

        guard let api else { return }
        do {
            let inserted = try await api.insertMemory(memory)
            if let idx = memories.firstIndex(where: { $0.id == memory.id }) {
                memories[idx] = inserted
            }
            renderer?.upsertNode(inserted)
            await loadTexture(for: inserted)
        } catch {
            // Surface a single failure glyph by leaving alpha low; future
            // retries handled by UploadPipeline.
        }
    }

    func toggleFocus(memoryID: UUID, currentZ: Float) {
        focus.toggleFocus(memoryID, currentZ: currentZ)
    }

    func dragNodeBy(id: UUID, delta: SIMD2<Float>) {
        guard let node = renderer?.nodes.first(where: { $0.memoryID == id }) else { return }
        node.position.x = max(-1, min(1, node.position.x + delta.x))
        node.position.y = max(-1, min(1, node.position.y + delta.y))
    }

    func commitDrag(id: UUID) async {
        guard
            let api,
            let node = renderer?.nodes.first(where: { $0.memoryID == id }),
            let idx = memories.firstIndex(where: { $0.id == id })
        else { return }
        memories[idx].posX = node.position.x
        memories[idx].posY = node.position.y
        memories[idx].posZ = node.position.z
        try? await api.updatePosition(memory: id, to: node.position)
    }

    private func applyMemories(_ list: [Memory]) {
        memories = list
        renderer?.setNodes(list)
    }

    private func loadTextures(for list: [Memory]) async {
        for m in list { await loadTexture(for: m) }
    }

    private func loadTexture(for memory: Memory) async {
        guard memory.kind != .text, let api else { return }
        let url = try? await api.signedURL(for: memory)
        if let tex = await TextureCache.shared.texture(for: memory, url: url) {
            renderer?.setTexture(tex, for: memory.id)
        }
    }
}
