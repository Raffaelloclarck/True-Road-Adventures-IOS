import Foundation

/// How the rider pays for a ride.
enum RidePaymentMethod: String, Codable, CaseIterable, Sendable {
    case cash = "CASH"
    case card = "CARD"
    case credits = "CREDITS"

    var labelKey: String {
        switch self {
        case .cash:    return "payment.method.cash"
        case .card:    return "payment.method.card"
        case .credits: return "payment.method.credits"
        }
    }

    var icon: String {
        switch self {
        case .cash:    return "banknote.fill"
        case .card:    return "creditcard.fill"
        case .credits: return "giftcard.fill"
        }
    }
}

/// Saved card returned by Stripe Customer.
struct SavedPaymentMethod: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let brand: String
    let last4: String
    let expMonth: Int
    let expYear: Int

    var displayLabel: String {
        let name = brand.capitalized
        return "\(name) •••• \(last4)"
    }

    var expiryLabel: String {
        String(format: "%02d/%02d", expMonth, expYear % 100)
    }
}
