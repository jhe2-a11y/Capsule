import Foundation

enum CollaboratorRole: String, Codable, Equatable {
    case owner
    case editor
}

struct Collaborator: Codable, Equatable {
    var capsuleID: UUID
    var userID: UUID
    var role: CollaboratorRole
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case capsuleID = "capsule_id"
        case userID    = "user_id"
        case role
        case createdAt = "created_at"
    }
}
