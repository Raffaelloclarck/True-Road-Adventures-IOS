import Foundation

enum DiscountCodeType: String, Codable, CaseIterable {
    case percentage = "PERCENTAGE"
    case fixed = "FIXED"

    var displayName: String {
        switch self {
        case .percentage: return "%"
        case .fixed: return "SRD"
        }
    }
}

struct DiscountCode: Identifiable, Codable, Hashable {
    let id: String
    var code: String
    var type: DiscountCodeType
    var value: Double
    var expiresAt: Date
    var isActive: Bool
    var maxUses: Int?
    var currentUses: Int
    var oncePerUser: Bool
    var usedByUserIds: [String]
    var minFare: Double?
    var description: String?
    var createdAt: Date
    var createdByAdminId: String

    var isExpired: Bool { expiresAt < Date() }

    var isMaxUsesReached: Bool {
        guard let max = maxUses else { return false }
        return currentUses >= max
    }

    func isValid(for fare: Double, userId: String) -> Bool {
        guard isActive, !isExpired, !isMaxUsesReached else { return false }
        if oncePerUser, usedByUserIds.contains(userId) { return false }
        if let min = minFare, fare < min { return false }
        return true
    }

    func discountAmount(for fare: Double) -> Double {
        switch type {
        case .percentage:
            return (fare * value / 100).rounded(.down)
        case .fixed:
            return min(value, fare)
        }
    }

    var statusLabel: String {
        if !isActive { return "Uitgeschakeld" }
        if isExpired { return "Verlopen" }
        if isMaxUsesReached { return "Limiet bereikt" }
        return "Actief"
    }
}
