import XCTest
@testable import True_Road_Adventures

final class RideRepositoryTests: XCTestCase {
    func testCreateAndAcceptRide() async throws {
        let repo = InMemoryRideRepository()
        let ride = try await repo.createRide(
            customerId: "customer",
            pickup: LatLng(latitude: 52.0, longitude: 4.0),
            destination: LatLng(latitude: 52.1, longitude: 4.1),
            scheduledAt: nil,
            pickupAddress: "A",
            destinationAddress: "B"
        )
        try await repo.acceptRide(ride.id, driverId: "driver")
        var received: Ride?
        let stream = repo.ride(by: ride.id)
        var iterator = stream.makeAsyncIterator()
        received = await iterator.next() ?? nil
        XCTAssertEqual(received?.driverId, "driver")
        XCTAssertEqual(received?.status, .accepted)
    }

    func testRealtimeFare() {
        let fare = FareCalculator.realtimeFare(distanceKm: 10, rideSeconds: 600, waitSeconds: 120)
        XCTAssertGreaterThan(fare, FareCalculator.startFare)
    }
}
