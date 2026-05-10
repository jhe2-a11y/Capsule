import Foundation

enum AccessRequestStatus: String, Codable, Equatable {
    case pending
    case accepted
    case declined
}

struct AccessRequest: Identifiable, Codable, Equatable {
    let id: UUID
    var capsuleID: UUID
    var requesterID: UUID
    var message: String?
    var status: AccessRequestStatus
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case capsuleID    = "capsule_id"
        case requesterID  = "requester_id"
        case message
        case status
        case createdAt    = "created_at"
    }
}
