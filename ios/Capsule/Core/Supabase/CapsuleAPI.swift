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
        try await client.from("capsules")
            .update(["access_mode": mode.rawValue])
            .eq("id", value: id.uuidString)
            .execute()
    }

    func setTitle(capsule id: UUID, title: String?) async throws {
        try await client.from("capsules")
            .update(["title": title as String?])
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

    func insertMemory(_ memory: Memory) async throws -> Memory {
        let inserted: Memory = try await client
            .from("memories")
            .insert(memory)
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
