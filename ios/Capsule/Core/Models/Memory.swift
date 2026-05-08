import Foundation
import CoreGraphics

enum MemoryKind: String, Codable, Equatable, CaseIterable {
    case photo, video, voice, text
}

struct Memory: Identifiable, Codable, Equatable {
    let id: UUID
    var capsuleID: UUID
    var kind: MemoryKind
    var storagePath: String?
    var textContent: String?
    var durationMs: Int?
    var posX: Float
    var posY: Float
    var posZ: Float
    var createdAt: Date
    var createdBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case capsuleID   = "capsule_id"
        case kind
        case storagePath = "storage_path"
        case textContent = "text_content"
        case durationMs  = "duration_ms"
        case posX        = "pos_x"
        case posY        = "pos_y"
        case posZ        = "pos_z"
        case createdAt   = "created_at"
        case createdBy   = "created_by"
    }
}

extension Memory {
    /// Stable spatial position vector in normalized capsule space.
    /// x,y in [-1,1]; z in [0,1] where 0 is most distant, 1 is foreground.
    var position: SIMD3<Float> { .init(posX, posY, posZ) }
}
