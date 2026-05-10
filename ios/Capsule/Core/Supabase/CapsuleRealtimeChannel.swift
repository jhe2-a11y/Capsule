import Foundation
import Supabase

/// Streams INSERT/UPDATE/DELETE on `memories` and UPDATEs on `capsules`
/// for a given capsule. Renamed from `RealtimeMemoryChannel` once the
/// surface widened to include capsule-level changes (title, access mode).
@MainActor
final class CapsuleRealtimeChannel {
    enum Event {
        case memoryInserted(Memory)
        case memoryUpdated(Memory)
        case memoryDeleted(UUID)
        case capsuleUpdated(Capsule)
    }

    private let client = SupabaseClientFactory.shared
    private var channel: RealtimeChannelV2?
    private let capsuleID: UUID
    private let onEvent: (Event) -> Void

    init(capsule id: UUID, onEvent: @escaping (Event) -> Void) {
        self.capsuleID = id
        self.onEvent = onEvent
    }

    func start() async {
        let channel = client.realtimeV2.channel("capsule:\(capsuleID.uuidString)")

        let memoryInserts = await channel.postgresChange(
            InsertAction.self, schema: "public", table: "memories",
            filter: "capsule_id=eq.\(capsuleID.uuidString)")
        let memoryUpdates = await channel.postgresChange(
            UpdateAction.self, schema: "public", table: "memories",
            filter: "capsule_id=eq.\(capsuleID.uuidString)")
        let memoryDeletes = await channel.postgresChange(
            DeleteAction.self, schema: "public", table: "memories",
            filter: "capsule_id=eq.\(capsuleID.uuidString)")
        let capsuleUpdates = await channel.postgresChange(
            UpdateAction.self, schema: "public", table: "capsules",
            filter: "id=eq.\(capsuleID.uuidString)")

        Task { for await change in memoryInserts {
            if let m: Memory = decode(change.record) { onEvent(.memoryInserted(m)) }
        }}
        Task { for await change in memoryUpdates {
            if let m: Memory = decode(change.record) { onEvent(.memoryUpdated(m)) }
        }}
        Task { for await change in memoryDeletes {
            // The version-fragile bit: AnyJSON's case access. Inline so a
            // breaking change in supabase-swift surfaces here, not in a helper.
            if case .string(let s)? = change.oldRecord["id"],
               let id = UUID(uuidString: s) { onEvent(.memoryDeleted(id)) }
        }}
        Task { for await change in capsuleUpdates {
            if let c: Capsule = decode(change.record) { onEvent(.capsuleUpdated(c)) }
        }}

        await channel.subscribe()
        self.channel = channel
    }

    func stop() async {
        if let c = channel {
            await c.unsubscribe()
            channel = nil
        }
    }

    private func decode<T: Decodable>(_ record: [String: AnyJSON]) -> T? {
        guard let data = try? JSONEncoder().encode(record) else { return nil }
        return try? JSONDecoder.capsule.decode(T.self, from: data)
    }
}

extension JSONDecoder {
    /// JSON decoder configured for the Capsule API: ISO-8601 dates with
    /// fractional-second tolerance.
    static var capsule: JSONDecoder {
        let d = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = withFraction.date(from: str) { return date }
            if let date = plain.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Bad date: \(str)")
        }
        return d
    }
}
