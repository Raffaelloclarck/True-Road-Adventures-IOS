import Foundation

enum RideStatus: String, Codable, CaseIterable {
    case idle = "IDLE"
    case searching = "SEARCHING"
    case accepted = "ACCEPTED"
    case arrived = "ARRIVED"
    case pickedUp = "PICKED_UP"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
}

enum PaymentStatus: String, Codable, CaseIterable {
    case pending = "PENDING"
    case paid = "PAID"
    case failed = "FAILED"
    case cash = "CASH"
}

enum ActiveRideStatus: String, Codable, CaseIterable {
    case idle = "IDLE"
    case riding = "RIDING"
    case waiting = "WAITING"
    case ended = "ENDED"
}

struct LatLng: Codable, Hashable {
    let latitude: Double
    let longitude: Double
}

struct Ride: Codable, Identifiable, Hashable {
    let id: String
    let customerId: String
    var driverId: String?
    var status: RideStatus
    var pickupLocation: LatLng
    var destinationLocation: LatLng
    var pickupAddress: String?
    var destinationAddress: String?
    var createdAt: Date
    var updatedAt: Date
    var price: Double?
    var paymentStatus: PaymentStatus?
    var driverLocation: LatLng?
    var driverBearing: Double?
    var customerLocation: LatLng?
    var customerLocationUpdatedAt: Date?
    var etaToPickupSeconds: Int?
    var scheduledAt: Date?
    var activeStatus: ActiveRideStatus
    var startTime: Date?
    var endTime: Date?
    var distanceKm: Double
    var rideSeconds: Int
    var waitSeconds: Int
    var startFare: Double
    var perKm: Double
    var perMinRide: Double
    var perMinWait: Double
    var totalFareRealtime: Double
    var totalFareFinal: Double?
    var tier: RideTier

    init(
        id: String = UUID().uuidString,
        customerId: String,
        driverId: String? = nil,
        status: RideStatus = .searching,
        pickupLocation: LatLng,
        destinationLocation: LatLng,
        pickupAddress: String? = nil,
        destinationAddress: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        price: Double? = nil,
        paymentStatus: PaymentStatus? = nil,
        driverLocation: LatLng? = nil,
        driverBearing: Double? = nil,
        customerLocation: LatLng? = nil,
        customerLocationUpdatedAt: Date? = nil,
        etaToPickupSeconds: Int? = nil,
        scheduledAt: Date? = nil,
        activeStatus: ActiveRideStatus = .idle,
        startTime: Date? = nil,
        endTime: Date? = nil,
        distanceKm: Double = 0,
        rideSeconds: Int = 0,
        waitSeconds: Int = 0,
        startFare: Double = FareCalculator.startFare,
        perKm: Double = FareCalculator.perKm,
        perMinRide: Double = FareCalculator.perMinRide,
        perMinWait: Double = FareCalculator.perMinWait,
        totalFareRealtime: Double = FareCalculator.startFare,
        totalFareFinal: Double? = nil,
        tier: RideTier = .standard
    ) {
        self.id = id
        self.customerId = customerId
        self.driverId = driverId
        self.status = status
        self.pickupLocation = pickupLocation
        self.destinationLocation = destinationLocation
        self.pickupAddress = pickupAddress
        self.destinationAddress = destinationAddress
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.price = price
        self.paymentStatus = paymentStatus
        self.driverLocation = driverLocation
        self.driverBearing = driverBearing
        self.customerLocation = customerLocation
        self.customerLocationUpdatedAt = customerLocationUpdatedAt
        self.etaToPickupSeconds = etaToPickupSeconds
        self.scheduledAt = scheduledAt
        self.activeStatus = activeStatus
        self.startTime = startTime
        self.endTime = endTime
        self.distanceKm = distanceKm
        self.rideSeconds = rideSeconds
        self.waitSeconds = waitSeconds
        self.startFare = startFare
        self.perKm = perKm
        self.perMinRide = perMinRide
        self.perMinWait = perMinWait
        self.totalFareRealtime = totalFareRealtime
        self.totalFareFinal = totalFareFinal
        self.tier = tier
    }
}

enum RideEvent: Equatable {
    case statusChanged(RideStatus)
    case paymentUpdated(PaymentStatus)
    case driverLocationUpdated(LatLng)
    case customerLocationUpdated(LatLng)
    case fareUpdated(Double)
}
