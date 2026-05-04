import Foundation

struct NavigationStep: Codable, Hashable {
    let instruction: String
    let distanceMeters: Int
    let durationSeconds: Int
    let endLat: Double
    let endLng: Double
    let maneuver: String?
}

struct DirectionsResult: Codable, Hashable {
    let points: [Coordinate2D]
    let steps: [NavigationStep]
    let totalDurationSeconds: Int
    let distanceKm: Double
    var trafficSegments: [TrafficSegment] = []
}

struct Coordinate2D: Codable, Hashable {
    let latitude: Double
    let longitude: Double
}

// MARK: - Traffic

enum TrafficSpeed: String, Codable {
    case normal     = "NORMAL"
    case slow       = "SLOW"
    case trafficJam = "TRAFFIC_JAM"
}

struct TrafficSegment: Codable, Hashable {
    let points: [Coordinate2D]
    let speed: TrafficSpeed
}
