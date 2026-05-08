import SwiftUI
import MetalKit
import simd

struct InteriorView: View {
    let capsuleID: UUID

    @EnvironmentObject private var session: AppSession
    @StateObject private var model = InteriorModel()
    @State private var composeKind: MemoryKind?
    @State private var showSettings = false
    @State private var foregroundedMediaURL: URL?

    var body: some View {
        ZStack {
            // Metal field
            DepthFieldHost(model: model)
                .ignoresSafeArea()

            // Foregrounded memory (text/photo/video/voice played fullscreen)
            if let focused = model.focusedMemory {
                ForegroundedMemoryView(memory: focused, mediaURL: foregroundedMediaURL)
                    .ignoresSafeArea()
                    .background(.black.opacity(0.55).ignoresSafeArea())
                    .onTapGesture { model.focus.dismiss() }
                    .task(id: focused.id) {
                        foregroundedMediaURL = try? await session.api.signedURL(for: focused)
                    }
            }

            // Edge-pull compose tray (owner/editor only)
            if model.canEdit && model.focus.focusedMemoryID == nil {
                ComposeTray(onSelect: { kind in composeKind = kind },
                            onLibrary: { session.openLibrary() },
                            onSettings: { showSettings = true })
            }
        }
        .task { await model.start(capsuleID: capsuleID, api: session.api, auth: session.auth) }
        .onDisappear { Task { await model.stop() } }
        .sheet(item: $composeKind) { kind in
            MemoryComposer(kind: kind, capsuleID: capsuleID) { memory in
                composeKind = nil
                Task { await model.didCompose(memory) }
            }
        }
        .sheet(isPresented: $showSettings) {
            CapsuleSettingsView(capsuleID: capsuleID)
        }
    }
}

// MARK: - Metal host

private struct DepthFieldHost: UIViewRepresentable {
    @ObservedObject var model: InteriorModel

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = model.renderer?.device ?? MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
        view.framebufferOnly = false
        view.preferredFramesPerSecond = 60
        view.isOpaque = true
        view.delegate = model.renderer
        view.isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.pan(_:)))
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.pinch(_:)))
        view.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)

        let long = UILongPressGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.longPress(_:)))
        long.minimumPressDuration = 0.45
        view.addGestureRecognizer(long)

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.delegate = model.renderer
        context.coordinator.model = model
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject {
        var model: InteriorModel
        private var dragStart: SIMD2<Float> = .zero
        private var draggingNodeID: UUID?
        private var pinchStartZ: Float = 0

        init(model: InteriorModel) { self.model = model }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let r = model.renderer, let v = g.view else { return }
            let p = g.translation(in: v)
            if let id = draggingNodeID {
                if g.state == .changed {
                    let vp = SIMD2<Float>(Float(v.bounds.width), Float(v.bounds.height))
                    let delta = SIMD2<Float>(Float(p.x), -Float(p.y)) / (vp * 0.5)
                    model.dragNodeBy(id: id, delta: delta)
                    g.setTranslation(.zero, in: v)
                }
                if g.state == .ended || g.state == .cancelled {
                    Task { await model.commitDrag(id: id) }
                    draggingNodeID = nil
                }
            } else {
                // pan field laterally → biases parallax
                if g.state == .changed {
                    r.parallaxOffsetPx += SIMD2<Float>(Float(p.x), -Float(p.y)) * 0.4
                    g.setTranslation(.zero, in: v)
                }
            }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard let r = model.renderer else { return }
            switch g.state {
            case .began: pinchStartZ = r.cameraDolly
            case .changed:
                let s = Float(g.scale)
                r.cameraDolly = max(-0.4, min(0.4, pinchStartZ + (s - 1) * 0.3))
            default: break
            }
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let r = model.renderer, let v = g.view, g.state == .ended else { return }
            let p = g.location(in: v)
            if let node = r.node(at: p, in: v.bounds.size) {
                model.toggleFocus(memoryID: node.memoryID, currentZ: node.position.z)
            } else {
                model.focus.dismiss()
            }
        }

        @objc func longPress(_ g: UILongPressGestureRecognizer) {
            guard let r = model.renderer, let v = g.view else { return }
            switch g.state {
            case .began:
                let p = g.location(in: v)
                if let node = r.node(at: p, in: v.bounds.size) {
                    draggingNodeID = node.memoryID
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            default: break
            }
        }
    }
}

// MARK: - Compose tray (edge-pull from bottom)

private struct ComposeTray: View {
    let onSelect: (MemoryKind) -> Void
    let onLibrary: () -> Void
    let onSettings: () -> Void
    @State private var open = false

    var body: some View {
        VStack {
            Spacer()
            ZStack {
                if open {
                    HStack(spacing: 26) {
                        affordance(systemImage: "photo", label: "Photo")  { onSelect(.photo) }
                        affordance(systemImage: "video", label: "Video")  { onSelect(.video) }
                        affordance(systemImage: "mic",   label: "Voice")  { onSelect(.voice) }
                        affordance(systemImage: "text.alignleft",
                                                        label: "Text")   { onSelect(.text)  }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(.bottom, 28)
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { v in
                    if v.translation.height < -30 { withAnimation(.spring) { open = true } }
                    if v.translation.height >  30 { withAnimation(.spring) { open = false } }
                }
        )
        .overlay(alignment: .topTrailing) {
            if open {
                HStack(spacing: 14) {
                    Button(action: onSettings) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Button(action: onLibrary) {
                        Image(systemName: "circle.grid.2x2")
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(20)
            }
        }
    }

    private func affordance(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .light))
                Text(label).font(.system(size: 11, design: .serif))
            }
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 56)
        }
    }
}

extension MemoryKind: Identifiable { public var id: String { rawValue } }
