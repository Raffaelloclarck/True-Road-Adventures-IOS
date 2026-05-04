import Foundation

enum RideTier: String, Codable, CaseIterable {
    case standard = "STANDARD"
    case comfort  = "COMFORT"
    case xl       = "XL"

    var multiplier: Double {
        switch self {
        case .standard: return 1.0
        case .comfort:  return 1.6
        case .xl:       return 2.1
        }
    }

    var displayName: String {
        switch self {
        case .standard: return "Standaard"
        case .comfort:  return "Comfort"
        case .xl:       return "XL"
        }
    }

    var icon: String {
        switch self {
        case .standard: return "car.fill"
        case .comfort:  return "car.2.fill"
        case .xl:       return "suv.side.fill"
        }
    }
}

enum FareCalculator {
    static let startFare: Double  = 40.0
    static let perKm: Double      = 30.0
    static let perMinRide: Double = 2.0
    static let perMinWait: Double = 3.33

    static func realtimeFare(
        distanceKm: Double,
        rideSeconds: Int,
        waitSeconds: Int,
        tier: RideTier = .standard
    ) -> Double {
        let rideMinutes = Double(rideSeconds) / 60.0
        let waitMinutes = Double(waitSeconds) / 60.0
        let base = startFare
            + (distanceKm * perKm)
            + (rideMinutes * perMinRide)
            + (waitMinutes * perMinWait)
        let scaled = base * tier.multiplier
        return max(scaled, startFare * tier.multiplier)
    }

    /// Returns the discounted fare and the amount of credits actually applied.
    /// Credits are capped at the full fare — the rider never pays negative.
    static func applyCredits(to fare: Double, credits: Double) -> (final: Double, applied: Double) {
        let applied = min(max(credits, 0), fare)
        return (max(0, fare - applied), applied)
    }
}
