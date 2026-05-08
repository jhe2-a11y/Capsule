import Foundation

enum AccessMode: String, Codable, Equatable {
    case open
    case `private`
}

struct Capsule: Identifiable, Codable, Equatable {
    let id: UUID
    var ownerID: UUID?
    var accessMode: AccessMode
    var title: String?
    var claimedAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID    = "owner_id"
        case accessMode = "access_mode"
        case title
        case claimedAt  = "claimed_at"
        case createdAt  = "created_at"
    }
}

extension Capsule {
    var isClaimed: Bool { ownerID != nil }
}
