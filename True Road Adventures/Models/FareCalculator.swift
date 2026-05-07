import Foundation

enum RideTier: String, Codable {
    case standard = "STANDARD"

    // nonisolated: Swift 6 may infer @MainActor for types used heavily from UI/services;
    // these are pure constants and must be readable from FareCalculator.realtimeFare, etc.
    nonisolated var multiplier: Double { 1.0 }
    nonisolated var displayName: String { "Standaard" }
    nonisolated var icon: String { "car.fill" }
}

enum FareCalculator {
    // nonisolated: Swift 6 can infer @MainActor for static members used mainly on the main
    // actor; defaults and call sites outside that actor must still read these constants.
    nonisolated static let startFare: Double  = 40.0
    nonisolated static let perKm: Double      = 30.0
    nonisolated static let perMinRide: Double = 2.0
    nonisolated static let perMinWait: Double = 3.33

    nonisolated static func realtimeFare(
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
    nonisolated static func applyCredits(to fare: Double, credits: Double) -> (final: Double, applied: Double) {
        let applied = min(max(credits, 0), fare)
        return (max(0, fare - applied), applied)
    }
}
