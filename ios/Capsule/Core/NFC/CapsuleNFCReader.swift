import Foundation
import CoreNFC

/// Reads NDEF-encoded Capsule URLs from a chip.
///
/// Concurrency model: this type is intentionally **not** `@MainActor`.
/// Core NFC delivers callbacks on a queue we don't own and the protocol
/// methods can't be marked `nonisolated` while the type is actor-isolated
/// without strict-concurrency complaints. Mutable state lives in a small
/// `Box` guarded by an unfair lock; the public `read()` API hops onto
/// the main actor for delivery so callers can use it as if it were
/// main-isolated.
final class CapsuleNFCReader: NSObject, @unchecked Sendable {
    static let shared = CapsuleNFCReader()

    var isAvailable: Bool { NFCNDEFReaderSession.readingAvailable }

    /// Begin a reader session. The system NFC sheet appears; on first
    /// read the session ends silently and the URL is returned.
    func read(prompt: String = "Hold your Capsule near the top of your phone.") async throws -> URL {
        guard NFCNDEFReaderSession.readingAvailable else {
            throw NFCError.unavailable
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            box.replace(continuation: cont)
            let s = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: true)
            s.alertMessage = prompt
            s.begin()
            box.replace(session: s)
        }
    }

    // MARK: state box

    private let box = Box()

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<URL, Error>?
        private var session: NFCNDEFReaderSession?

        func replace(continuation: CheckedContinuation<URL, Error>) {
            lock.withLock { self.continuation = continuation }
        }
        func replace(session: NFCNDEFReaderSession?) {
            lock.withLock { self.session = session }
        }
        func takeContinuation() -> CheckedContinuation<URL, Error>? {
            lock.withLock {
                let c = continuation
                continuation = nil
                return c
            }
        }
        func clearSession() { lock.withLock { session = nil } }
    }
}

extension CapsuleNFCReader: NFCNDEFReaderSessionDelegate {
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        for msg in messages {
            for record in msg.records {
                if let url = Self.url(from: record) {
                    box.takeContinuation()?.resume(returning: url)
                    return
                }
            }
        }
        box.takeContinuation()?.resume(throwing: NFCError.noURL)
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        box.takeContinuation()?.resume(throwing: error)
        box.clearSession()
    }

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) { }

    /// NDEF Type==U records use 1-byte URI prefix codes.
    private static let uriPrefixes: [String] = [
        "", "http://www.", "https://www.", "http://", "https://",
        "tel:", "mailto:", "ftp://anonymous:anonymous@", "ftp://ftp.",
        "ftps://", "sftp://", "smb://", "nfs://", "ftp://", "dav://",
        "news:", "telnet://", "imap:", "rtsp://", "urn:", "pop:",
        "sip:", "sips:", "tftp:", "btspp://", "btl2cap://", "btgoep://",
        "tcpobex://", "irdaobex://", "file://", "urn:epc:id:",
        "urn:epc:tag:", "urn:epc:pat:", "urn:epc:raw:", "urn:epc:",
        "urn:nfc:",
    ]

    private static func url(from record: NFCNDEFPayload) -> URL? {
        guard record.typeNameFormat == .nfcWellKnown,
              String(data: record.type, encoding: .utf8) == "U",
              record.payload.count > 0 else { return nil }
        let prefixIdx = Int(record.payload[0])
        let prefix = prefixIdx < uriPrefixes.count ? uriPrefixes[prefixIdx] : ""
        let rest = String(data: record.payload.dropFirst(), encoding: .utf8) ?? ""
        return URL(string: prefix + rest)
    }
}

enum NFCError: Error { case unavailable, noURL }
