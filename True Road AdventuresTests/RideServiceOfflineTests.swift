import XCTest
import Network
@testable import True_Road_Adventures

final class RideServiceOfflineTests: XCTestCase {
    private let samplePickup = LatLng(latitude: 52.3731, longitude: 4.8922)
    private let sampleDestination = LatLng(latitude: 52.3105, longitude: 4.7683)

    func testRequestRideFailsWhenOffline() async {
        let repo = InMemoryRideRepository()
        let navigation = NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil))
        let service = RideService(repository: repo, navigationManager: navigation, networkMonitor: NetworkMonitor(mockStatus: .requiresConnection))

        await XCTAssertThrowsError(
            try await service.requestRide(
                customerId: "c1",
                pickup: samplePickup,
                destination: sampleDestination,
                pickupAddress: "A",
                destinationAddress: "B",
                scheduledAt: nil
            )
        ) { error in
            XCTAssertTrue(error is RideService.RideActionError)
        }
    }

    func testAcceptRideSucceedsWhenOnline() async throws {
        let repo = InMemoryRideRepository()
        let navigation = NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil))
        let service = RideService(repository: repo, navigationManager: navigation, networkMonitor: NetworkMonitor(mockStatus: .satisfied))
        let ride = try await repo.createRide(
            customerId: "c1",
            pickup: samplePickup,
            destination: sampleDestination,
            scheduledAt: nil,
            pickupAddress: "A",
            destinationAddress: "B"
        )

        try await service.acceptRide(ride.id, driverId: "d1")

        var iterator = repo.ride(by: ride.id).makeAsyncIterator()
        let updated = await iterator.next() ?? nil
        XCTAssertEqual(updated??.driverId, "d1")
        XCTAssertEqual(updated??.status, .accepted)
    }
}
