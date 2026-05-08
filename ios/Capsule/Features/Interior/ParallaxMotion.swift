import Foundation
import CoreMotion
import simd

/// Subscribes to device attitude and produces a small px offset to feed the
/// renderer's parallax. Amplitude is intentionally small — the world should
/// *respond*, not swing.
@MainActor
final class ParallaxMotion {
    private let manager = CMMotionManager()
    private(set) var offsetPx: SIMD2<Float> = .zero
    private var amplitudePx: Float = 18

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // Roll/pitch in radians; clamp to ±0.4 (~23°) so motion stays calm.
            let pitch = Float(max(-0.4, min(0.4, motion.attitude.pitch)))
            let roll  = Float(max(-0.4, min(0.4, motion.attitude.roll)))
            // Smooth toward target (low-pass), to avoid jitter.
            let target = SIMD2<Float>(roll, pitch) / 0.4 * self.amplitudePx
            self.offsetPx = self.offsetPx * 0.85 + target * 0.15
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        offsetPx = .zero
    }
}
