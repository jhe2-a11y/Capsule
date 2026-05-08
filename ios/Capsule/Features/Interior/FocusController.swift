import Foundation
import simd

/// Pull-forward state machine. A tap on a node "pulls it forward": the field
/// dollies until the focused node sits near z=1, others recede with desat
/// + blur. Dismiss returns the camera to neutral.
@MainActor
final class FocusController: ObservableObject {
    enum State: Equatable {
        case browsing
        case focused(memoryID: UUID)
        case settling(memoryID: UUID?)   // animating between states
    }

    @Published private(set) var state: State = .browsing

    /// Current dolly applied by the camera (additive to instance.worldPos.z).
    @Published private(set) var dolly: Float = 0

    var focusedMemoryID: UUID? {
        if case let .focused(id) = state { return id }
        if case let .settling(id) = state { return id }
        return nil
    }

    func focus(_ id: UUID, currentZ: Float) {
        // Compute a dolly that brings the focused node near z = 0.95.
        dolly = max(0, min(0.5, 0.95 - currentZ))
        state = .settling(memoryID: id)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if case .settling(let mid) = state, mid == id {
                state = .focused(memoryID: id)
            }
        }
    }

    func dismiss() {
        state = .settling(memoryID: nil)
        dolly = 0
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if case .settling(nil) = state { state = .browsing }
        }
    }

    func toggleFocus(_ id: UUID, currentZ: Float) {
        if focusedMemoryID == id { dismiss() } else { focus(id, currentZ: currentZ) }
    }
}
