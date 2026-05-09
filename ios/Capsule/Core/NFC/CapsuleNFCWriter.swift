import CoreNFC
import Foundation

/// Writes a Capsule Universal Link to a blank (or rewritable) NDEF tag.
///
/// Two callers exist for this:
///   1. The shop / factory provisioning utility — encode a chip with the
///      pre-seeded capsule UUID before it ships to the customer.
///   2. The owner's "re-encode" affordance — replace a damaged or lost chip
///      bound to an existing capsule.
///
/// Consumer reading is handled by `CapsuleNFCReader`. We deliberately keep
/// these in separate types: the writer surface is rarely shown, and
/// conflating them would leak the technology into the everyday read path.
@MainActor
final class CapsuleNFCWriter: NSObject {
    static let shared = CapsuleNFCWriter()

    enum WriteError: Error {
        case unavailable
        case noTag
        case readOnly
        case writeFailed(String)
    }

    private var session: NFCNDEFReaderSession?
    private var continuation: CheckedContinuation<Void, Error>?
    private var pendingURL: URL?

    /// Encode `url` onto the next NDEF tag the user holds to the phone.
    func write(url: URL,
               prompt: String = "Hold a blank Capsule chip near the top of your phone.") async throws {
        guard NFCNDEFReaderSession.readingAvailable else {
            throw WriteError.unavailable
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            self.pendingURL = url
            // invalidateAfterFirstRead must be false so we get the
            // didDetect-tags callback (rather than only didDetectNDEFs).
            let s = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
            s.alertMessage = prompt
            s.begin()
            self.session = s
        }
    }
}

extension CapsuleNFCWriter: NFCNDEFReaderSessionDelegate {
    nonisolated func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) { }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // We rely on `didDetect tags:` for writing; this is unused when
        // invalidateAfterFirstRead == false but the protocol still requires it.
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No chip found.")
            Task { @MainActor in self.finish(throwing: WriteError.noTag) }
            return
        }

        if tags.count > 1 {
            session.alertMessage = "More than one chip — try one at a time."
            session.invalidate(errorMessage: "Multiple chips detected.")
            Task { @MainActor in self.finish(throwing: WriteError.writeFailed("multiple tags")) }
            return
        }

        Task { @MainActor in
            guard let url = self.pendingURL else {
                session.invalidate(errorMessage: "Nothing to write.")
                self.finish(throwing: WriteError.writeFailed("no payload"))
                return
            }

            session.connect(to: tag) { [weak self] err in
                guard let self else { return }
                if let err {
                    session.invalidate(errorMessage: "Couldn’t connect.")
                    Task { @MainActor in self.finish(throwing: err) }
                    return
                }
                tag.queryNDEFStatus { status, _, statusErr in
                    if let statusErr {
                        session.invalidate(errorMessage: "Couldn’t read this chip.")
                        Task { @MainActor in self.finish(throwing: statusErr) }
                        return
                    }
                    switch status {
                    case .notSupported, .readOnly:
                        session.invalidate(errorMessage: "This chip can’t be written.")
                        Task { @MainActor in self.finish(throwing: WriteError.readOnly) }
                    case .readWrite:
                        let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url)
                        guard let payload else {
                            session.invalidate(errorMessage: "Bad URL.")
                            Task { @MainActor in self.finish(throwing: WriteError.writeFailed("invalid url")) }
                            return
                        }
                        let message = NFCNDEFMessage(records: [payload])
                        tag.writeNDEF(message) { writeErr in
                            if let writeErr {
                                session.invalidate(errorMessage: "Couldn’t write.")
                                Task { @MainActor in self.finish(throwing: writeErr) }
                                return
                            }
                            session.alertMessage = "Capsule encoded."
                            session.invalidate()
                            Task { @MainActor in self.finish(throwing: nil) }
                        }
                    @unknown default:
                        session.invalidate(errorMessage: "Unknown chip state.")
                        Task { @MainActor in self.finish(throwing: WriteError.writeFailed("unknown status")) }
                    }
                }
            }
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            // Only surface as failure if we haven't already resolved (the
            // happy path invalidates after a successful write and is finished
            // before this delegate call).
            if self.continuation != nil {
                self.finish(throwing: error)
            }
        }
    }

    private func finish(throwing error: Error?) {
        let cont = continuation
        continuation = nil
        pendingURL = nil
        session = nil
        if let error { cont?.resume(throwing: error) }
        else         { cont?.resume(returning: ()) }
    }
}
