import Foundation

struct DriverLocationUpdate: Codable, Hashable {
    let latLng: LatLng
    let speedKmh: Double
    let heading: Double?
    let timestamp: Date

    init(latLng: LatLng, speedKmh: Double, heading: Double? = nil, timestamp: Date = .now) {
        self.latLng = latLng
        self.speedKmh = speedKmh
        self.heading = heading
        self.timestamp = timestamp
    }
}
