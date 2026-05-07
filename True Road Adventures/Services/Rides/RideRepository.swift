import Foundation

@MainActor
protocol RideRepository {
    func createRide(
        customerId: String,
        pickup: LatLng,
        destination: LatLng,
        scheduledAt: Date?,
        pickupAddress: String?,
        destinationAddress: String?,
        tier: RideTier,
        estimatedFare: Double,
        appliedDiscountCode: String?,
        discountAmount: Double?
    ) async throws -> Ride

    func ridesForCustomer(_ customerId: String) -> AsyncStream<[Ride]>
    func ridesForDriver(_ driverId: String) -> AsyncStream<[Ride]>
    func availableRides() -> AsyncStream<[Ride]>
    func allRides() -> AsyncStream<[Ride]>
    func ride(by id: String) -> AsyncStream<Ride?>

    func acceptRide(_ rideId: String, driverId: String) async throws
    func updateDriverLocation(_ rideId: String, location: LatLng, bearing: Double?) async throws
    func updateCustomerLocation(_ rideId: String, location: LatLng) async throws
    func updateRideStatus(_ rideId: String, status: RideStatus) async throws
    func updateEta(_ rideId: String, seconds: Int?) async throws
    func updateFareRealtime(_ rideId: String, distanceKm: Double, rideSeconds: Int, waitSeconds: Int, totalFare: Double) async throws
    func finalizeRide(_ rideId: String, distanceKm: Double, rideSeconds: Int, waitSeconds: Int, totalFareFinal: Double) async throws
    func setPaymentStatus(_ rideId: String, status: PaymentStatus) async throws
    func submitRating(_ rating: Rating) async throws
}

enum RideCancelError: LocalizedError {
    case notCancellable
    var errorDescription: String? {
        String(localized: "ride.cancel.error.driver_accepted")
    }
}

@MainActor
final class InMemoryRideRepository: RideRepository {
    private var rides: [String: Ride] = [:]
    private var rideStreams: [String: AsyncStream<Ride?>.Continuation] = [:]
    private var availableStreams: [AsyncStream<[Ride]>.Continuation] = []
    private var allRidesStreams: [AsyncStream<[Ride]>.Continuation] = []
    private var customerStreams: [String: AsyncStream<[Ride]>.Continuation] = [:]
    private var driverStreams: [String: AsyncStream<[Ride]>.Continuation] = [:]
    private var expiryTask: Task<Void, Never>?

    static let requestExpirySeconds: TimeInterval = 10 * 60

    init() {
        startExpiryLoop()
    }

    private func startExpiryLoop() {
        expiryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { return }
                self.expireStaleRides()
            }
        }
    }

    private func expireStaleRides() {
        let cutoff = Date.now.addingTimeInterval(-Self.requestExpirySeconds)
        let expired = rides.values.filter {
            $0.status == .searching &&
            $0.scheduledAt == nil &&
            $0.createdAt < cutoff
        }
        for var ride in expired {
            ride.status = .cancelled
            ride.updatedAt = .now
            rides[ride.id] = ride
            broadcast(ride)
        }
    }

    func createRide(
        customerId: String,
        pickup: LatLng,
        destination: LatLng,
        scheduledAt: Date?,
        pickupAddress: String?,
        destinationAddress: String?,
        tier: RideTier,
        estimatedFare: Double,
        appliedDiscountCode: String?,
        discountAmount: Double?
    ) async throws -> Ride {
        var ride = Ride(
            customerId: customerId,
            pickupLocation: pickup,
            destinationLocation: destination,
            pickupAddress: pickupAddress,
            destinationAddress: destinationAddress,
            scheduledAt: scheduledAt,
            totalFareRealtime: estimatedFare,
            tier: tier,
            appliedDiscountCode: appliedDiscountCode,
            discountAmount: discountAmount
        )
        ride.status = .searching
        rides[ride.id] = ride
        broadcast(ride)
        return ride
    }

    func ridesForCustomer(_ customerId: String) -> AsyncStream<[Ride]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [Ride].self)
        customerStreams[customerId] = continuation
        continuation.yield(currentCustomerRides(customerId))
        return stream
    }

    func ridesForDriver(_ driverId: String) -> AsyncStream<[Ride]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [Ride].self)
        driverStreams[driverId] = continuation
        continuation.yield(currentDriverRides(driverId))
        return stream
    }

    func availableRides() -> AsyncStream<[Ride]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [Ride].self)
        availableStreams.append(continuation)
        continuation.yield(currentAvailableRides())
        return stream
    }

    func allRides() -> AsyncStream<[Ride]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [Ride].self)
        allRidesStreams.append(continuation)
        continuation.yield(currentAllRides())
        return stream
    }

    func ride(by id: String) -> AsyncStream<Ride?> {
        let (stream, continuation) = AsyncStream.makeStream(of: (Ride?).self)
        rideStreams[id] = continuation
        continuation.yield(rides[id])
        return stream
    }

    func acceptRide(_ rideId: String, driverId: String) async throws {
        guard var ride = rides[rideId], ride.status == .searching else {
            throw NSError(domain: "Ride", code: 409, userInfo: [NSLocalizedDescriptionKey: "Ride niet beschikbaar"])
        }
        ride.driverId = driverId
        ride.status = .accepted
        ride.updatedAt = .now
        rides[rideId] = ride
        broadcast(ride)
    }

    func updateDriverLocation(_ rideId: String, location: LatLng, bearing: Double?) async throws {
        guard var ride = rides[rideId] else { return }
        ride.driverLocation = location
        ride.driverBearing = bearing
        ride.updatedAt = .now
        rides[rideId] = ride
        broadcast(ride)
    }

    func updateCustomerLocation(_ rideId: String, location: LatLng) async throws {
        guard var ride = rides[rideId] else { return }
        ride.customerLocation = location
        ride.customerLocationUpdatedAt = .now
        ride.updatedAt = .now
        rides[rideId] = ride
        broadcast(ride)
    }

    func updateRideStatus(_ rideId: String, status: RideStatus) async throws {
        guard var ride = rides[rideId] else { return }
        if status == .cancelled && ride.status != .searching {
            throw RideCancelError.notCancellable
        }
        ride.status = status
        ride.updatedAt = .now
        if status == .completed {
            ride.paymentStatus = .pending
        }
        rides[rideId] = ride
        broadcast(ride)
    }

    func updateEta(_ rideId: String, seconds: Int?) async throws {
        guard var ride = rides[rideId] else { return }
        ride.etaToPickupSeconds = seconds
        ride.updatedAt = .now
        rides[rideId] = ride
        broadcast(ride)
    }

    func updateFareRealtime(_ rideId: String, distanceKm: Double, rideSeconds: Int, waitSeconds: Int, totalFare: Double) async throws {
        guard var ride = rides[rideId] else { return }
        ride.distanceKm = distanceKm
        ride.rideSeconds = rideSeconds
        ride.waitSeconds = waitSeconds
        ride.totalFareRealtime = totalFare
        ride.updatedAt = .now
        rides[rideId] = ride
        broadcast(ride)
    }

    func finalizeRide(_ rideId: String, distanceKm: Double, rideSeconds: Int, waitSeconds: Int, totalFareFinal: Double) async throws {
        guard var ride = rides[rideId] else { return }
        ride.distanceKm = distanceKm
        ride.rideSeconds = rideSeconds
        ride.waitSeconds = waitSeconds
        ride.totalFareFinal = totalFareFinal
        ride.totalFareRealtime = totalFareFinal
        ride.activeStatus = .ended
        ride.status = .completed
        ride.paymentStatus = .pending
        ride.endTime = .now
        ride.updatedAt = .now
        rides[rideId] = ride
        broadcast(ride)
    }

    func setPaymentStatus(_ rideId: String, status: PaymentStatus) async throws {
        guard var ride = rides[rideId] else { return }
        ride.paymentStatus = status
        ride.updatedAt = .now
        rides[rideId] = ride
        broadcast(ride)
    }

    func submitRating(_ rating: Rating) async throws {
        // In-memory: no persistence needed
    }

    private func broadcast(_ ride: Ride) {
        rideStreams[ride.id]?.yield(ride)
        availableStreams.forEach { $0.yield(currentAvailableRides()) }
        allRidesStreams.forEach { $0.yield(currentAllRides()) }
        if let driverId = ride.driverId {
            driverStreams[driverId]?.yield(currentDriverRides(driverId))
        }
        customerStreams[ride.customerId]?.yield(currentCustomerRides(ride.customerId))
    }

    private func currentAllRides() -> [Ride] {
        rides.values.sorted { $0.createdAt > $1.createdAt }
    }

    private func currentAvailableRides() -> [Ride] {
        rides.values.filter { $0.status == .searching }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func currentCustomerRides(_ customerId: String) -> [Ride] {
        rides.values.filter { $0.customerId == customerId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func currentDriverRides(_ driverId: String) -> [Ride] {
        rides.values.filter { $0.driverId == driverId }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

/// API-backed implementation intended for production builds.
@MainActor
final class ApiRideRepository: RideRepository {
    private let client: ApiClient
    private let tokenProvider: () async -> String?

    init(client: ApiClient, tokenProvider: @escaping () async -> String?) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    func createRide(
        customerId: String,
        pickup: LatLng,
        destination: LatLng,
        scheduledAt: Date?,
        pickupAddress: String?,
        destinationAddress: String?,
        tier: RideTier,
        estimatedFare: Double,
        appliedDiscountCode: String?,
        discountAmount: Double?
    ) async throws -> Ride {
        let request = ApiRequest(
            path: "/rides",
            method: "POST",
            body: RideCreateRequest(
                customerId: customerId,
                pickup: pickup,
                destination: destination,
                scheduledAt: scheduledAt,
                pickupAddress: pickupAddress,
                destinationAddress: destinationAddress,
                tier: tier.rawValue,
                estimatedFare: estimatedFare,
                appliedDiscountCode: appliedDiscountCode,
                discountAmount: discountAmount
            )
        )
        return try await send(request)
    }

    func ridesForCustomer(_ customerId: String) -> AsyncStream<[Ride]> {
        makePollingStream(request: ApiRequest(path: "/rides/customer/\(customerId)"))
    }

    func ridesForDriver(_ driverId: String) -> AsyncStream<[Ride]> {
        makePollingStream(request: ApiRequest(path: "/rides/driver/\(driverId)"))
    }

    func availableRides() -> AsyncStream<[Ride]> {
        makePollingStream(request: ApiRequest(path: "/rides/available"))
    }

    func allRides() -> AsyncStream<[Ride]> {
        makePollingStream(request: ApiRequest(path: "/rides/all"))
    }

    func ride(by id: String) -> AsyncStream<Ride?> {
        let (stream, continuation) = AsyncStream.makeStream(of: (Ride?).self)
        let task = Task { [weak self] in
            var delay: UInt64 = 3_000_000_000
            while !Task.isCancelled {
                guard let self else { break }
                do {
                    let ride: Ride = try await send(.init(path: "/rides/\(id)"))
                    continuation.yield(ride)
                    delay = 3_000_000_000
                } catch {
                    continuation.yield(nil)
                    delay = min(delay * 2, 30_000_000_000)
                }
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
        return stream
    }

    func acceptRide(_ rideId: String, driverId: String) async throws {
        let request = ApiRequest(path: "/rides/\(rideId)/accept", method: "POST", body: ["driverId": driverId])
        let _: EmptyResponse = try await send(request)
    }

    func updateDriverLocation(_ rideId: String, location: LatLng, bearing: Double?) async throws {
        let request = ApiRequest(
            path: "/rides/\(rideId)/driver-location",
            method: "POST",
            body: DriverLocationBody(location: location, bearing: bearing)
        )
        let _: EmptyResponse = try await send(request)
    }

    func updateCustomerLocation(_ rideId: String, location: LatLng) async throws {
        let request = ApiRequest(path: "/rides/\(rideId)/customer-location", method: "POST", body: ["location": location])
        let _: EmptyResponse = try await send(request)
    }

    func updateRideStatus(_ rideId: String, status: RideStatus) async throws {
        let request = ApiRequest(path: "/rides/\(rideId)/status", method: "POST", body: ["status": status.rawValue])
        let _: EmptyResponse = try await send(request)
    }

    func updateEta(_ rideId: String, seconds: Int?) async throws {
        let request = ApiRequest(path: "/rides/\(rideId)/eta", method: "POST", body: ["seconds": seconds])
        let _: EmptyResponse = try await send(request)
    }

    func updateFareRealtime(_ rideId: String, distanceKm: Double, rideSeconds: Int, waitSeconds: Int, totalFare: Double) async throws {
        let request = ApiRequest(
            path: "/rides/\(rideId)/fare/realtime",
            method: "POST",
            body: FareRealtimeBody(distanceKm: distanceKm, rideSeconds: rideSeconds, waitSeconds: waitSeconds, totalFare: totalFare)
        )
        let _: EmptyResponse = try await send(request)
    }

    func finalizeRide(_ rideId: String, distanceKm: Double, rideSeconds: Int, waitSeconds: Int, totalFareFinal: Double) async throws {
        let request = ApiRequest(
            path: "/rides/\(rideId)/fare/finalize",
            method: "POST",
            body: FinalizeRideBody(distanceKm: distanceKm, rideSeconds: rideSeconds, waitSeconds: waitSeconds, totalFareFinal: totalFareFinal)
        )
        let _: EmptyResponse = try await send(request)
    }

    func setPaymentStatus(_ rideId: String, status: PaymentStatus) async throws {
        let request = ApiRequest(path: "/rides/\(rideId)/payment", method: "POST", body: ["status": status.rawValue])
        let _: EmptyResponse = try await send(request)
    }

    func submitRating(_ rating: Rating) async throws {
        let request = ApiRequest(path: "/rides/\(rating.rideId)/rating", method: "POST", body: rating)
        let _: EmptyResponse = try await send(request)
    }

    // MARK: - Helpers

    private func makePollingStream(request: ApiRequest) -> AsyncStream<[Ride]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [Ride].self)
        let task = Task { [weak self] in
            var delay: UInt64 = 3_000_000_000
            while !Task.isCancelled {
                guard let self else { break }
                do {
                    let rides: [Ride] = try await send(request)
                    continuation.yield(rides)
                    delay = 3_000_000_000
                } catch {
                    continuation.yield([])
                    delay = min(delay * 2, 30_000_000_000)
                }
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
        return stream
    }

    private func send<T: Decodable>(_ request: ApiRequest) async throws -> T {
        guard let token = await tokenProvider() else {
            throw ApiError.unauthorized
        }
        return try await client.send(request, decode: T.self, token: token)
    }

    // MARK: - Request body types

    private struct RideCreateRequest: Encodable {
        let customerId: String
        let pickup: LatLng
        let destination: LatLng
        let scheduledAt: Date?
        let pickupAddress: String?
        let destinationAddress: String?
        let tier: String
        let estimatedFare: Double
        let appliedDiscountCode: String?
        let discountAmount: Double?
    }

    private struct DriverLocationBody: Encodable {
        let location: LatLng
        let bearing: Double?
    }

    private struct FareRealtimeBody: Encodable {
        let distanceKm: Double
        let rideSeconds: Int
        let waitSeconds: Int
        let totalFare: Double
    }

    private struct FinalizeRideBody: Encodable {
        let distanceKm: Double
        let rideSeconds: Int
        let waitSeconds: Int
        let totalFareFinal: Double
    }

    private struct EmptyResponse: Decodable { }
}
