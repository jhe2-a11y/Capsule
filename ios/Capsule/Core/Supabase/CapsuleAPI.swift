import Foundation
import Supabase

/// Thin façade over PostgREST + Edge Functions. Keeps the repo concerns
/// (RLS-aware reads, atomic claim, signed URLs) in one place.
@MainActor
final class CapsuleAPI {
    static let shared = CapsuleAPI()
    private let client = SupabaseClientFactory.shared

    // MARK: capsules

    func fetchCapsule(id: UUID) async throws -> Capsule? {
        let rows: [Capsule] = try await client
            .from("capsules")
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func myCapsules() async throws -> [Capsule] {
        try await client
            .from("capsules")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func setAccessMode(capsule id: UUID, mode: AccessMode) async throws {
        struct Patch: Encodable { let access_mode: String }
        try await client.from("capsules")
            .update(Patch(access_mode: mode.rawValue))
            .eq("id", value: id.uuidString)
            .execute()
    }

    func setTitle(capsule id: UUID, title: String?) async throws {
        // Explicit struct so `nil` encodes as JSON null and clears the
        // column. A `[String: String?]` literal would omit the key and
        // leave the existing value in place.
        struct Patch: Encodable { let title: String? }
        try await client.from("capsules")
            .update(Patch(title: title))
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Atomic claim. Returns the row on success; throws on race / not found.
    func claim(capsule id: UUID) async throws -> Capsule {
        struct Params: Encodable { let p_capsule: String }
        let row: Capsule = try await client
            .rpc("claim_capsule", params: Params(p_capsule: id.uuidString))
            .execute()
            .value
        return row
    }

    // MARK: memories

    func fetchMemories(capsule id: UUID) async throws -> [Memory] {
        try await client
            .from("memories")
            .select()
            .eq("capsule_id", value: id.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    /// Insert via a DTO that omits `created_at`, so the server's
    /// `default now()` fills it. Avoids the client's clock leaking into
    /// memory ordering and works regardless of the PostgREST encoder's
    /// Date strategy.
    func insertMemory(_ memory: Memory) async throws -> Memory {
        let payload = MemoryInsert(memory: memory)
        let inserted: Memory = try await client
            .from("memories")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return inserted
    }

    func updatePosition(memory id: UUID, to p: SIMD3<Float>) async throws {
        struct Patch: Encodable {
            let pos_x: Float; let pos_y: Float; let pos_z: Float
        }
        try await client
            .from("memories")
            .update(Patch(pos_x: p.x, pos_y: p.y, pos_z: p.z))
            .eq("id", value: id.uuidString)
            .execute()
    }

    func deleteMemory(id: UUID) async throws {
        try await client
            .from("memories")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: media URLs

    func signedURL(for memory: Memory) async throws -> URL? {
        guard memory.storagePath != nil else { return nil }
        struct Body: Encodable { let memory_id: String }
        struct Resp: Decodable { let url: String }
        let resp: Resp = try await client.functions.invoke(
            "get-memory-url",
            options: .init(body: Body(memory_id: memory.id.uuidString))
        )
        return URL(string: resp.url)
    }

    // MARK: invites / collaborators

    func createInvite(capsule id: UUID) async throws -> String {
        struct Body: Encodable { let capsule_id: String }
        struct Resp: Decodable { let token: String }
        let resp: Resp = try await client.functions.invoke(
            "create-invite",
            options: .init(body: Body(capsule_id: id.uuidString))
        )
        return resp.token
    }

    func redeemInvite(token: String) async throws -> UUID {
        struct Body: Encodable { let token: String }
        struct Resp: Decodable { let capsule_id: String }
        let resp: Resp = try await client.functions.invoke(
            "redeem-invite",
            options: .init(body: Body(token: token))
        )
        guard let id = UUID(uuidString: resp.capsule_id) else {
            throw URLError(.badServerResponse)
        }
        return id
    }

    func requestAccess(capsule id: UUID, message: String?) async throws {
        struct Body: Encodable { let capsule_id: String; let message: String? }
        let _: [String: Bool] = try await client.functions.invoke(
            "request-access",
            options: .init(body: Body(capsule_id: id.uuidString, message: message))
        )
    }

    // MARK: access requests (owner-side)

    func accessRequests(capsule id: UUID) async throws -> [AccessRequest] {
        try await client
            .from("access_requests")
            .select()
            .eq("capsule_id", value: id.uuidString)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Atomic accept via a SECURITY DEFINER edge function: flips the
    /// request status to `accepted` and inserts the requester into
    /// `capsule_collaborators` in one transaction.
    func acceptAccessRequest(id: UUID) async throws {
        struct Body: Encodable { let request_id: String }
        let _: [String: Bool] = try await client.functions.invoke(
            "accept-access-request",
            options: .init(body: Body(request_id: id.uuidString))
        )
    }

    func declineAccessRequest(id: UUID) async throws {
        struct Patch: Encodable { let status: String }
        try await client.from("access_requests")
            .update(Patch(status: "declined"))
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: storage upload

    func uploadMedia(
        capsule capsuleID: UUID,
        memoryID: UUID,
        kind: MemoryKind,
        data: Data,
        contentType: String
    ) async throws -> String {
        let ext: String
        switch kind {
        case .photo: ext = "jpg"
        case .video: ext = "mp4"
        case .voice: ext = "m4a"
        case .text:  return ""
        }
        let path = "\(capsuleID.uuidString)/\(memoryID.uuidString).\(ext)"
        _ = try await client.storage
            .from("capsule-media")
            .upload(
                path: path,
                file: data,
                options: .init(contentType: contentType, upsert: false)
            )
        return path
    }
}

/// Encodable shape sent to PostgREST when inserting a memory. Mirrors
/// `Memory` but omits `created_at` so the server's default now() fills it.
private struct MemoryInsert: Encodable {
    let id: UUID
    let capsule_id: UUID
    let kind: String
    let storage_path: String?
    let text_content: String?
    let duration_ms: Int?
    let pos_x: Float
    let pos_y: Float
    let pos_z: Float
    let created_by: UUID?

    init(memory m: Memory) {
        self.id = m.id
        self.capsule_id = m.capsuleID
        self.kind = m.kind.rawValue
        self.storage_path = m.storagePath
        self.text_content = m.textContent
        self.duration_ms = m.durationMs
        self.pos_x = m.posX
        self.pos_y = m.posY
        self.pos_z = m.posZ
        self.created_by = m.createdBy
    }
}
