import Foundation
import Combine

@MainActor
final class RideService: ObservableObject {
    enum RideActionError: Error {
        case offline
    }

    @Published private(set) var activeRide: Ride?
    @Published private(set) var availableRides: [Ride] = []
    @Published private(set) var customerHistory: [Ride] = []
    @Published private(set) var driverHistory: [Ride] = []
    @Published private(set) var adminRides: [Ride] = []

    private let repository: RideRepository
    private let navigationManager: NavigationSessionManager
    private let networkMonitor: NetworkMonitor?
    private let analytics: AnalyticsService?
    private var streams: [Task<Void, Never>] = []
    private var currentUserId: String?

    init(repository: RideRepository, navigationManager: NavigationSessionManager, networkMonitor: NetworkMonitor? = nil, analytics: AnalyticsService? = nil) {
        self.repository = repository
        self.navigationManager = navigationManager
        self.networkMonitor = networkMonitor
        self.analytics = analytics
    }

    func attachUser(_ user: User?) {
        streams.forEach { $0.cancel() }
        streams.removeAll()
        currentUserId = user?.id
        guard let user else { return }

        streams.append(Task { [weak self] in
            guard let self else { return }
            if user.role == .customer {
                for await rides in repository.ridesForCustomer(user.id) {
                    await MainActor.run {
                        self.customerHistory = rides
                        self.activeRide = rides.first(where: { $0.status != .completed && $0.status != .cancelled })
                    }
                }
            } else if user.role == .admin {
                for await rides in repository.allRides() {
                    await MainActor.run {
                        self.adminRides = rides
                    }
                }
            } else {
                for await rides in repository.ridesForDriver(user.id) {
                    await MainActor.run {
                        self.driverHistory = rides
                        self.activeRide = rides.first(where: { $0.status != .completed && $0.status != .cancelled })
                    }
                }
            }
        })

        if user.role == .driver {
            streams.append(Task { [weak self] in
                guard let self else { return }
                for await rides in repository.availableRides() {
                    await MainActor.run {
                        self.availableRides = rides
                    }
                }
            })
        }
    }

    func requestRide(customerId: String, pickup: LatLng, destination: LatLng, pickupAddress: String?, destinationAddress: String?, scheduledAt: Date?, tier: RideTier, estimatedFare: Double) async throws {
        try ensureOnline()
        let ride = try await repository.createRide(
            customerId: customerId,
            pickup: pickup,
            destination: destination,
            scheduledAt: scheduledAt,
            pickupAddress: pickupAddress,
            destinationAddress: destinationAddress,
            tier: tier,
            estimatedFare: estimatedFare
        )
        await MainActor.run {
            activeRide = ride
        }
        analytics?.track("ride.requested", properties: [
            "customerId": customerId,
            "tier": tier.rawValue,
            "estimatedFare": "\(estimatedFare)",
            "scheduled": scheduledAt != nil ? "true" : "false"
        ])
    }

    func acceptRide(_ rideId: String, driverId: String) async throws {
        try ensureOnline()
        try await repository.acceptRide(rideId, driverId: driverId)
        analytics?.track("ride.accepted", properties: ["rideId": rideId, "driverId": driverId])
    }

    func updateDriverLocation(_ rideId: String, location: LatLng, bearing: Double?) async throws {
        try ensureOnline()
        try await repository.updateDriverLocation(rideId, location: location, bearing: bearing)
    }

    func updateCustomerLocation(_ rideId: String, location: LatLng) async throws {
        try ensureOnline()
        try await repository.updateCustomerLocation(rideId, location: location)
    }

    func updateStatus(_ rideId: String, status: RideStatus) async throws {
        try ensureOnline()
        try await repository.updateRideStatus(rideId, status: status)
        analytics?.track("ride.status", properties: ["rideId": rideId, "status": status.rawValue])
    }

    func updateEta(_ rideId: String, seconds: Int?) async throws {
        try ensureOnline()
        try await repository.updateEta(rideId, seconds: seconds)
        if let seconds {
            analytics?.track("ride.eta", properties: ["rideId": rideId, "etaSeconds": "\(seconds)"])
        }
    }

    func updateFare(_ rideId: String, distanceKm: Double, rideSeconds: Int, waitSeconds: Int, tier: RideTier) async throws {
        try ensureOnline()
        let total = FareCalculator.realtimeFare(distanceKm: distanceKm, rideSeconds: rideSeconds, waitSeconds: waitSeconds, tier: tier)
        try await repository.updateFareRealtime(rideId, distanceKm: distanceKm, rideSeconds: rideSeconds, waitSeconds: waitSeconds, totalFare: total)
        analytics?.track("ride.fare.realtime", properties: [
            "rideId": rideId,
            "distanceKm": "\(distanceKm)",
            "rideSeconds": "\(rideSeconds)",
            "waitSeconds": "\(waitSeconds)",
            "tier": tier.rawValue,
            "total": "\(total)"
        ])
    }

    func finalizeRide(_ rideId: String, distanceKm: Double, rideSeconds: Int, waitSeconds: Int, totalFareFinal: Double) async throws {
        try ensureOnline()
        try await repository.finalizeRide(rideId, distanceKm: distanceKm, rideSeconds: rideSeconds, waitSeconds: waitSeconds, totalFareFinal: totalFareFinal)
        analytics?.track("ride.fare.finalized", properties: [
            "rideId": rideId,
            "total": "\(totalFareFinal)"
        ])
    }

    func submitRating(rideId: String, fromUserId: String, toUserId: String, score: Int, comment: String? = nil) async throws {
        try ensureOnline()
        let rating = Rating(
            rideId: rideId,
            fromUserId: fromUserId,
            toUserId: toUserId,
            score: score,
            comment: comment
        )
        try await repository.submitRating(rating)
        analytics?.track("ride.rated", properties: ["rideId": rideId, "score": "\(score)"])
    }

    func setPaymentStatus(_ rideId: String, status: PaymentStatus) async throws {
        try ensureOnline()
        try await repository.setPaymentStatus(rideId, status: status)
        analytics?.track("ride.payment", properties: ["rideId": rideId, "status": status.rawValue])
    }

    func subscribeToRide(_ rideId: String) -> AsyncStream<Ride?> {
        repository.ride(by: rideId)
    }

    var navigationSnapshot: NavigationSessionManager.Snapshot {
        navigationManager.snapshot
    }

    var navigationSnapshotPublisher: AnyPublisher<NavigationSessionManager.Snapshot, Never> {
        navigationManager.$snapshot.eraseToAnyPublisher()
    }

    var navigationEventsPublisher: AnyPublisher<NavigationSessionManager.Event, Never> {
        navigationManager.events.eraseToAnyPublisher()
    }

    func startNavigation(origin: LatLng, destination: LatLng, onRouteLoaded: @escaping (DirectionsResult) -> Void) {
        navigationManager.startNewRoute(origin: origin, target: destination, onRouteLoaded: onRouteLoaded)
    }

    func onLocation(_ rideId: String, update: DriverLocationUpdate, onReroute: @escaping (DirectionsResult) -> Void = { _ in }) {
        navigationManager.onLocation(rideId, update: update, onReroute: onReroute)
    }

    func fetchRoute(from origin: LatLng, to destination: LatLng) async -> DirectionsResult {
        await navigationManager.fetchRoute(from: origin, to: destination)
    }

    func stopNavigation() {
        navigationManager.stop()
    }

    private func ensureOnline() throws {
        if let monitor = networkMonitor, !monitor.isOnline {
            throw RideActionError.offline
        }
    }
}
