import Foundation

/// A parsed tap. Represents either an NFC read or a Universal Link / custom
/// scheme deep link. Both routes converge here.
struct TapIntent: Equatable {
    enum Source: Equatable { case nfc, link }
    let capsuleID: UUID
    let source: Source
    let inviteToken: String?

    static func parse(_ url: URL) -> TapIntent? {
        // Accept both:
        //   https://capsule.app/c/<uuid>[?invite=<token>]
        //   capsule://c/<uuid>[?invite=<token>]
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let host = comps.host ?? ""
        let path = comps.path
        let scheme = (url.scheme ?? "").lowercased()

        let pathSegments: [String]
        if scheme == "capsule" {
            // capsule://c/<uuid>  → host = "c", path = "/<uuid>"
            pathSegments = ([host] + path.split(separator: "/").map(String.init))
                .filter { !$0.isEmpty }
        } else {
            pathSegments = path.split(separator: "/").map(String.init)
        }

        guard pathSegments.count >= 2,
              pathSegments[0] == "c",
              let id = UUID(uuidString: pathSegments[1])
        else { return nil }

        let invite = comps.queryItems?.first(where: { $0.name == "invite" })?.value
        return TapIntent(capsuleID: id, source: .link, inviteToken: invite)
    }
}
