import Foundation

struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let userId: String

    // nonisolated prevents Swift 6 from inferring @MainActor isolation on these
    // members, keeping AuthSession usable from any actor (e.g. ApiAuthRepository,
    // FirebaseAuthRepository).
    nonisolated init(accessToken: String, refreshToken: String?, userId: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.userId = userId
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken   = try c.decode(String.self,          forKey: .accessToken)
        refreshToken  = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        userId        = try c.decode(String.self,          forKey: .userId)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accessToken,          forKey: .accessToken)
        try c.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try c.encode(userId,               forKey: .userId)
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, userId
    }
}
