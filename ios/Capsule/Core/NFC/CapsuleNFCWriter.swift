import CoreNFC
import Foundation

/// Writes a Capsule Universal Link to a blank (or rewritable) NDEF tag.
///
/// Two callers exist:
///   1. The shop / factory provisioning utility — encode a chip with the
///      pre-seeded capsule UUID before it ships to the customer.
///   2. The owner's "re-encode" affordance — replace a damaged or lost
///      chip bound to an existing capsule.
///
/// Concurrency model mirrors `CapsuleNFCReader`: not `@MainActor`, with
/// mutable state behind a lock-guarded `Box` so the Core NFC callbacks
/// (which arrive on Apple's queue) can mutate without violating
/// `SWIFT_STRICT_CONCURRENCY: complete`.
final class CapsuleNFCWriter: NSObject, @unchecked Sendable {
    static let shared = CapsuleNFCWriter()

    enum WriteError: Error {
        case unavailable
        case noTag
        case readOnly
        case writeFailed(String)
    }

    /// Encode `url` onto the next NDEF tag the user holds to the phone.
    func write(url: URL,
               prompt: String = "Hold a blank Capsule chip near the top of your phone.") async throws {
        guard NFCNDEFReaderSession.readingAvailable else {
            throw WriteError.unavailable
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            box.start(continuation: cont, url: url)
            // invalidateAfterFirstRead must be false so we get the
            // didDetect-tags callback (rather than only didDetectNDEFs).
            let s = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
            s.alertMessage = prompt
            s.begin()
            box.set(session: s)
        }
    }

    // MARK: state box

    private let box = Box()

    fileprivate final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        private var session: NFCNDEFReaderSession?
        private(set) var pendingURL: URL?

        func start(continuation: CheckedContinuation<Void, Error>, url: URL) {
            lock.withLock {
                self.continuation = continuation
                self.pendingURL = url
            }
        }
        func set(session: NFCNDEFReaderSession?) {
            lock.withLock { self.session = session }
        }
        func takeContinuation() -> CheckedContinuation<Void, Error>? {
            lock.withLock {
                let c = continuation
                continuation = nil
                pendingURL = nil
                return c
            }
        }
        func currentURL() -> URL? {
            lock.withLock { pendingURL }
        }
    }
}

extension CapsuleNFCWriter: NFCNDEFReaderSessionDelegate {
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) { }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Unused when invalidateAfterFirstRead == false; we drive writing
        // from `didDetect tags:` instead.
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No chip found.")
            box.takeContinuation()?.resume(throwing: WriteError.noTag)
            return
        }
        if tags.count > 1 {
            session.invalidate(errorMessage: "More than one chip — try one at a time.")
            box.takeContinuation()?.resume(throwing: WriteError.writeFailed("multiple tags"))
            return
        }
        guard let url = box.currentURL() else {
            session.invalidate(errorMessage: "Nothing to write.")
            box.takeContinuation()?.resume(throwing: WriteError.writeFailed("no payload"))
            return
        }

        // Bind only Sendable / value-type captures into the Core NFC
        // closures. `box` is reference-but-Sendable; `url`, `session`,
        // and `tag` are values from this scope.
        let box = self.box
        session.connect(to: tag) { connectErr in
            if let connectErr {
                session.invalidate(errorMessage: "Couldn’t connect.")
                box.takeContinuation()?.resume(throwing: connectErr)
                return
            }
            tag.queryNDEFStatus { status, _, statusErr in
                if let statusErr {
                    session.invalidate(errorMessage: "Couldn’t read this chip.")
                    box.takeContinuation()?.resume(throwing: statusErr)
                    return
                }
                switch status {
                case .notSupported, .readOnly:
                    session.invalidate(errorMessage: "This chip can’t be written.")
                    box.takeContinuation()?.resume(throwing: WriteError.readOnly)
                case .readWrite:
                    guard let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) else {
                        session.invalidate(errorMessage: "Bad URL.")
                        box.takeContinuation()?.resume(throwing: WriteError.writeFailed("invalid url"))
                        return
                    }
                    let message = NFCNDEFMessage(records: [payload])
                    tag.writeNDEF(message) { writeErr in
                        if let writeErr {
                            session.invalidate(errorMessage: "Couldn’t write.")
                            box.takeContinuation()?.resume(throwing: writeErr)
                            return
                        }
                        session.alertMessage = "Capsule encoded."
                        session.invalidate()
                        box.takeContinuation()?.resume(returning: ())
                    }
                @unknown default:
                    session.invalidate(errorMessage: "Unknown chip state.")
                    box.takeContinuation()?.resume(throwing: WriteError.writeFailed("unknown status"))
                }
            }
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // Only surface as failure if we haven't already resolved (the
        // happy path invalidates after a successful write and is finished
        // before this delegate call).
        box.takeContinuation()?.resume(throwing: error)
    }
}
