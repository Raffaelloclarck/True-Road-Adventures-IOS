import Foundation

struct Rating: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let rideId: String
    let fromUserId: String
    let toUserId: String
    let score: Int
    let comment: String?
    let createdAt: Date

    nonisolated init(
        id: String = UUID().uuidString,
        rideId: String,
        fromUserId: String,
        toUserId: String,
        score: Int,
        comment: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.rideId = rideId
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.score = score
        self.comment = comment
        self.createdAt = createdAt
    }
}
