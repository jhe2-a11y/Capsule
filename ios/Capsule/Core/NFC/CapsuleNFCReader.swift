import Foundation
import CoreNFC

/// Reads NDEF-encoded Capsule URLs from a chip. NFC writing is intentionally
/// confined to the (separate) provisioning utility; the consumer-facing app
/// reads only.
@MainActor
final class CapsuleNFCReader: NSObject, ObservableObject {
    static let shared = CapsuleNFCReader()

    @Published var lastTap: URL?
    private var session: NFCNDEFReaderSession?
    private var continuation: CheckedContinuation<URL, Error>?

    var isAvailable: Bool { NFCNDEFReaderSession.readingAvailable }

    /// Begin a reader session. The system NFC sheet appears; on first read
    /// the session ends silently and the URL is returned.
    func read(prompt: String = "Hold your Capsule near the top of your phone.") async throws -> URL {
        guard NFCNDEFReaderSession.readingAvailable else {
            throw NFCError.unavailable
        }
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let s = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: true)
            s.alertMessage = prompt
            s.begin()
            self.session = s
        }
    }
}

extension CapsuleNFCReader: NFCNDEFReaderSessionDelegate {
    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        for msg in messages {
            for record in msg.records {
                if let url = Self.url(from: record) {
                    Task { @MainActor in
                        self.lastTap = url
                        self.continuation?.resume(returning: url)
                        self.continuation = nil
                    }
                    return
                }
            }
        }
        Task { @MainActor in
            self.continuation?.resume(throwing: NFCError.noURL)
            self.continuation = nil
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: error)
            self.continuation = nil
            self.session = nil
        }
    }

    nonisolated func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) { }

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
