import Foundation

/// Optimistic-then-confirmed upload. The caller hands over raw bytes and a
/// pre-allocated memory ID; the pipeline uploads to Supabase Storage and
/// returns the storage path. Failures are retried with backoff.
@MainActor
final class UploadPipeline {
    static let shared = UploadPipeline()
    private let api = CapsuleAPI.shared

    enum UploadError: Error { case maxRetries }

    func upload(
        capsuleID: UUID,
        memoryID: UUID,
        kind: MemoryKind,
        data: Data,
        contentType: String,
        maxAttempts: Int = 4
    ) async throws -> String {
        var attempt = 0
        while attempt < maxAttempts {
            do {
                return try await api.uploadMedia(
                    capsule: capsuleID,
                    memoryID: memoryID,
                    kind: kind,
                    data: data,
                    contentType: contentType)
            } catch {
                attempt += 1
                if attempt >= maxAttempts { throw error }
                let delayNs = UInt64(pow(2.0, Double(attempt)) * 500_000_000)
                try? await Task.sleep(nanoseconds: delayNs)
            }
        }
        throw UploadError.maxRetries
    }
}
