import CoreMotion
import Foundation
import simd

/// Subscribes to device attitude and produces a small px offset to feed
/// the renderer's parallax. Amplitude is intentionally small — the
/// world should *respond*, not swing.
///
/// Concurrency: the CMMotionManager callback runs on the queue we hand
/// it (here, `.main`). To keep this clean under
/// `SWIFT_STRICT_CONCURRENCY: complete`, the type is `Sendable` and the
/// mutating offset lives in a lock-guarded box; the closure captures
/// only the box, not `self`.
final class ParallaxMotion: @unchecked Sendable {
    private let manager = CMMotionManager()
    private let box = OffsetBox()

    var offsetPx: SIMD2<Float> { box.read() }

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        let box = self.box
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let motion else { return }
            // Roll/pitch in radians; clamp to ±0.4 (~23°) so motion stays calm.
            let pitch = Float(max(-0.4, min(0.4, motion.attitude.pitch)))
            let roll  = Float(max(-0.4, min(0.4, motion.attitude.roll)))
            box.update(pitch: pitch, roll: roll)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        box.reset()
    }
}

private final class OffsetBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: SIMD2<Float> = .zero
    private let amplitudePx: Float = 18

    func read() -> SIMD2<Float> {
        lock.withLock { value }
    }

    func update(pitch: Float, roll: Float) {
        let target = SIMD2<Float>(roll, pitch) / 0.4 * amplitudePx
        lock.withLock {
            value = value * 0.85 + target * 0.15
        }
    }

    func reset() {
        lock.withLock { value = .zero }
    }
}
