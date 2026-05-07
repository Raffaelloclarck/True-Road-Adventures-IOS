import Foundation
import FirebaseFirestore

// MARK: - FirestoreRideRepository

/// Firestore-backed implementation of RideRepository.
/// Field names and types match the Android RideRepositoryImpl exactly:
///   - Locations  → GeoPoint
///   - Timestamps → Int64 milliseconds since epoch
///   - Enums      → UPPERCASE String (rawValue)
@MainActor
final class FirestoreRideRepository: RideRepository {

    private lazy var db: Firestore = Firestore.firestore()
    private var collection: CollectionReference { db.collection("rides") }

    // MARK: - Create

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
        let ref = collection.document()
        let now = msNow()
        var data: [String: Any] = [
            "customerId":        customerId,
            "pickup":            geoPoint(pickup),
            "destination":       geoPoint(destination),
            "status":            RideStatus.searching.rawValue,
            "activeStatus":      ActiveRideStatus.idle.rawValue,
            "paymentStatus":     PaymentStatus.pending.rawValue,
            "createdAt":         now,
            "updatedAt":         now,
            "distanceKm":        0.0,
            "rideSeconds":       Int64(0),
            "waitSeconds":       Int64(0),
            "startFare":         FareCalculator.startFare * tier.multiplier,
            "perKm":             FareCalculator.perKm,
            "perMinRide":        FareCalculator.perMinRide,
            "perMinWait":        FareCalculator.perMinWait,
            "totalFareRealtime": estimatedFare,
            "tier":              tier.rawValue,
        ]
        if let address = pickupAddress        { data["pickupAddress"]       = address }
        if let address = destinationAddress   { data["destinationAddress"]  = address }
        if let scheduled = scheduledAt        { data["scheduledAt"]         = msFrom(scheduled) }
        if let code = appliedDiscountCode     { data["appliedDiscountCode"] = code }
        if let amount = discountAmount, amount > 0 { data["discountAmount"] = amount }

        try await ref.setData(data)

        return Ride(
            id: ref.documentID,
            customerId: customerId,
            status: .searching,
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
    }

    // MARK: - Streams

    func ridesForCustomer(_ customerId: String) -> AsyncStream<[Ride]> {
        makeQueryStream(
            collection
                .whereField("customerId", isEqualTo: customerId)
                .order(by: "createdAt", descending: true)
        )
    }

    func ridesForDriver(_ driverId: String) -> AsyncStream<[Ride]> {
        makeQueryStream(
            collection
                .whereField("driverId", isEqualTo: driverId)
                .order(by: "createdAt", descending: true)
        )
    }

    func availableRides() -> AsyncStream<[Ride]> {
        makeQueryStream(
            collection
                .whereField("status", isEqualTo: RideStatus.searching.rawValue)
                .order(by: "createdAt", descending: true)
        )
    }

    func allRides() -> AsyncStream<[Ride]> {
        makeQueryStream(collection.order(by: "createdAt", descending: true))
    }

    func ride(by id: String) -> AsyncStream<Ride?> {
        let (stream, continuation) = AsyncStream.makeStream(of: (Ride?).self)
        let listener = collection.document(id).addSnapshotListener { snapshot, _ in
            guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                continuation.yield(nil)
                return
            }
            continuation.yield(rideFromDocument(id: snapshot.documentID, data: data))
        }
        continuation.onTermination = { @Sendable _ in listener.remove() }
        return stream
    }

    // MARK: - Driver operations

    func acceptRide(_ rideId: String, driverId: String) async throws {
        let ref = collection.document(rideId)
        _ = try await db.runTransaction { transaction, errorPointer in
            let doc: DocumentSnapshot
            do {
                doc = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            guard let status = doc.data()?["status"] as? String,
                  status == RideStatus.searching.rawValue else {
                errorPointer?.pointee = NSError(
                    domain: "RideRepository",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Rit niet meer beschikbaar"]
                )
                return nil
            }
            transaction.updateData([
                "driverId":  driverId,
                "status":    RideStatus.accepted.rawValue,
                "updatedAt": msNow(),
            ], forDocument: ref)
            return nil
        }
    }

    func updateDriverLocation(_ rideId: String, location: LatLng, bearing: Double?) async throws {
        var data: [String: Any] = [
            "driverLocation": geoPoint(location),
            "updatedAt":      msNow(),
        ]
        if let bearing { data["driverBearing"] = bearing }
        try await collection.document(rideId).updateData(data)
    }

    func updateCustomerLocation(_ rideId: String, location: LatLng) async throws {
        try await collection.document(rideId).updateData([
            "customerLocation":           geoPoint(location),
            "customerLocationUpdatedAt":  msNow(),
            "updatedAt":                  msNow(),
        ])
    }

    func updateRideStatus(_ rideId: String, status: RideStatus) async throws {
        try await collection.document(rideId).updateData([
            "status":    status.rawValue,
            "updatedAt": msNow(),
        ])
    }

    func updateEta(_ rideId: String, seconds: Int?) async throws {
        if let seconds {
            try await collection.document(rideId).updateData([
                "etaToPickupSeconds": Int64(seconds),
                "updatedAt":          msNow(),
            ])
        } else {
            try await collection.document(rideId).updateData([
                "etaToPickupSeconds": FieldValue.delete(),
                "updatedAt":          msNow(),
            ])
        }
    }

    func updateFareRealtime(
        _ rideId: String,
        distanceKm: Double,
        rideSeconds: Int,
        waitSeconds: Int,
        totalFare: Double
    ) async throws {
        try await collection.document(rideId).updateData([
            "distanceKm":        distanceKm,
            "rideSeconds":       Int64(rideSeconds),
            "waitSeconds":       Int64(waitSeconds),
            "totalFareRealtime": totalFare,
            "updatedAt":         msNow(),
        ])
    }

    func finalizeRide(
        _ rideId: String,
        distanceKm: Double,
        rideSeconds: Int,
        waitSeconds: Int,
        totalFareFinal: Double
    ) async throws {
        try await collection.document(rideId).updateData([
            "distanceKm":        distanceKm,
            "rideSeconds":       Int64(rideSeconds),
            "waitSeconds":       Int64(waitSeconds),
            "totalFareFinal":    totalFareFinal,
            "totalFareRealtime": totalFareFinal,
            "status":            RideStatus.completed.rawValue,
            "activeStatus":      ActiveRideStatus.ended.rawValue,
            "paymentStatus":     PaymentStatus.pending.rawValue,
            "endTime":           msNow(),
            "updatedAt":         msNow(),
        ])
    }

    func setPaymentStatus(_ rideId: String, status: PaymentStatus) async throws {
        try await collection.document(rideId).updateData([
            "paymentStatus": status.rawValue,
            "updatedAt":     msNow(),
        ])
    }

    func submitRating(_ rating: Rating) async throws {
        let data: [String: Any] = [
            "rideId":      rating.rideId,
            "fromUserId":  rating.fromUserId,
            "toUserId":    rating.toUserId,
            "score":       rating.score,
            "comment":     rating.comment ?? "",
            "createdAt":   msFrom(rating.createdAt),
        ]
        try await db.collection("ratings").document(rating.id).setData(data)
    }

    // MARK: - Private helpers

    private func makeQueryStream(_ query: Query) -> AsyncStream<[Ride]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [Ride].self)
        let listener = query.addSnapshotListener { snapshot, error in
            if let error {
                print("[FirestoreRideRepository] Listener error: \(error.localizedDescription)")
                continuation.yield([])
                return
            }
            let rides = snapshot?.documents.compactMap {
                rideFromDocument(id: $0.documentID, data: $0.data())
            } ?? []
            continuation.yield(rides)
        }
        continuation.onTermination = { @Sendable _ in listener.remove() }
        return stream
    }
}

// MARK: - Conversion helpers (free functions, no actor isolation needed)

private func msNow() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}

private func msFrom(_ date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970 * 1000)
}

private func dateFrom(ms: Any?) -> Date {
    guard let num = ms as? NSNumber else { return Date() }
    return Date(timeIntervalSince1970: num.doubleValue / 1000)
}

private func dateFromOpt(ms: Any?) -> Date? {
    guard let num = ms as? NSNumber else { return nil }
    return Date(timeIntervalSince1970: num.doubleValue / 1000)
}

private func geoPoint(_ latlng: LatLng) -> GeoPoint {
    GeoPoint(latitude: latlng.latitude, longitude: latlng.longitude)
}

private func latLngFrom(_ value: Any?) -> LatLng? {
    guard let gp = value as? GeoPoint else { return nil }
    return LatLng(latitude: gp.latitude, longitude: gp.longitude)
}

private func rideFromDocument(id: String, data: [String: Any]) -> Ride? {
    guard
        let customerId = data["customerId"] as? String,
        let pickup     = latLngFrom(data["pickup"]),
        let destination = latLngFrom(data["destination"])
    else { return nil }

    let statusStr  = data["status"] as? String ?? ""
    let status     = RideStatus(rawValue: statusStr) ?? .idle
    let activeStr  = data["activeStatus"] as? String ?? ""
    let active     = ActiveRideStatus(rawValue: activeStr) ?? .idle
    let payStr     = data["paymentStatus"] as? String
    let payment    = payStr.flatMap { PaymentStatus(rawValue: $0) }
    let tierStr    = data["tier"] as? String ?? RideTier.standard.rawValue
    let tier       = RideTier(rawValue: tierStr) ?? .standard

    return Ride(
        id:                          id,
        customerId:                  customerId,
        driverId:                    data["driverId"] as? String,
        status:                      status,
        pickupLocation:              pickup,
        destinationLocation:         destination,
        pickupAddress:               data["pickupAddress"] as? String,
        destinationAddress:          data["destinationAddress"] as? String,
        createdAt:                   dateFrom(ms: data["createdAt"]),
        updatedAt:                   dateFrom(ms: data["updatedAt"]),
        price:                       data["price"] as? Double,
        paymentStatus:               payment,
        driverLocation:              latLngFrom(data["driverLocation"]),
        driverBearing:               (data["driverBearing"] as? Double) ?? (data["driverBearing"] as? NSNumber)?.doubleValue,
        customerLocation:            latLngFrom(data["customerLocation"]),
        customerLocationUpdatedAt:   dateFromOpt(ms: data["customerLocationUpdatedAt"]),
        etaToPickupSeconds:          (data["etaToPickupSeconds"] as? NSNumber)?.intValue,
        scheduledAt:                 dateFromOpt(ms: data["scheduledAt"]),
        activeStatus:                active,
        startTime:                   dateFromOpt(ms: data["startTime"]),
        endTime:                     dateFromOpt(ms: data["endTime"]),
        distanceKm:                  (data["distanceKm"] as? NSNumber)?.doubleValue ?? 0,
        rideSeconds:                 (data["rideSeconds"] as? NSNumber)?.intValue ?? 0,
        waitSeconds:                 (data["waitSeconds"] as? NSNumber)?.intValue ?? 0,
        startFare:                   (data["startFare"] as? NSNumber)?.doubleValue ?? FareCalculator.startFare,
        perKm:                       (data["perKm"] as? NSNumber)?.doubleValue ?? FareCalculator.perKm,
        perMinRide:                  (data["perMinRide"] as? NSNumber)?.doubleValue ?? FareCalculator.perMinRide,
        perMinWait:                  (data["perMinWait"] as? NSNumber)?.doubleValue ?? FareCalculator.perMinWait,
        totalFareRealtime:           (data["totalFareRealtime"] as? NSNumber)?.doubleValue ?? FareCalculator.startFare,
        totalFareFinal:              (data["totalFareFinal"] as? NSNumber)?.doubleValue,
        tier:                        tier,
        appliedDiscountCode:         data["appliedDiscountCode"] as? String,
        discountAmount:              (data["discountAmount"] as? NSNumber)?.doubleValue
    )
}
