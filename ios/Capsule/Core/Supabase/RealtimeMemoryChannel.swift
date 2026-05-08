import Foundation
import Supabase

/// Streams INSERT/UPDATE/DELETE on `memories` for a given capsule.
@MainActor
final class RealtimeMemoryChannel {
    enum Event {
        case insert(Memory)
        case update(Memory)
        case delete(UUID)
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

        let inserts = await channel.postgresChange(
            InsertAction.self, schema: "public", table: "memories",
            filter: "capsule_id=eq.\(capsuleID.uuidString)")
        let updates = await channel.postgresChange(
            UpdateAction.self, schema: "public", table: "memories",
            filter: "capsule_id=eq.\(capsuleID.uuidString)")
        let deletes = await channel.postgresChange(
            DeleteAction.self, schema: "public", table: "memories",
            filter: "capsule_id=eq.\(capsuleID.uuidString)")

        Task { for await change in inserts {
            if let m = decode(change.record) { onEvent(.insert(m)) }
        }}
        Task { for await change in updates {
            if let m = decode(change.record) { onEvent(.update(m)) }
        }}
        Task { for await change in deletes {
            if let s = change.oldRecord["id"]?.stringValue,
               let id = UUID(uuidString: s) { onEvent(.delete(id)) }
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

    private func decode(_ record: [String: AnyJSON]) -> Memory? {
        guard let data = try? JSONEncoder().encode(record) else { return nil }
        return try? JSONDecoder.capsule.decode(Memory.self, from: data)
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
