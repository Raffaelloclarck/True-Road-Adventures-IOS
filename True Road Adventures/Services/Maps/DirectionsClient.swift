import Foundation

final class DirectionsClient {
    private let session: URLSession
    private let apiKey: String?

    private static let endpoint = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!

    // Fields needed for turn-by-turn navigation; field masking reduces billing cost.
    // routes.legs.polyline is the leg-level polyline whose indices match speedReadingIntervals.
    private static let fieldMask = [
        "routes.legs.steps.navigationInstruction",
        "routes.legs.steps.polyline.encodedPolyline",
        "routes.legs.steps.endLocation",
        "routes.legs.steps.distanceMeters",
        "routes.legs.steps.staticDuration",
        "routes.legs.polyline.encodedPolyline",
        "routes.legs.travelAdvisory.speedReadingIntervals",
        "routes.legs.duration",
        "routes.legs.distanceMeters",
        "routes.polyline.encodedPolyline"
    ].joined(separator: ",")

    init(session: URLSession = .shared, apiKey: String?) {
        self.session = session
        self.apiKey = apiKey
    }

    func fetch(origin: LatLng, destination: LatLng) async -> DirectionsResult {
        let lang = UserDefaults.standard.string(forKey: "app_language") ?? "nl"
        guard let apiKey, !apiKey.isEmpty else {
            return await fetchOSRM(origin: origin, destination: destination)
        }

        // First attempt: full request with traffic data (requires Roads/Traffic billing tier).
        // Second attempt: simplified request compatible with the basic Routes API billing tier.
        let requests: [(label: String, body: [String: Any])] = [
            ("full", [
                "origin": ["location": ["latLng": ["latitude": origin.latitude, "longitude": origin.longitude]]],
                "destination": ["location": ["latLng": ["latitude": destination.latitude, "longitude": destination.longitude]]],
                "travelMode": "DRIVE",
                "routingPreference": "TRAFFIC_AWARE_OPTIMAL",
                "languageCode": lang,
                "units": "METRIC",
                "polylineQuality": "HIGH_QUALITY",
                "extraComputations": ["TRAFFIC_ON_POLYLINE"]
            ]),
            ("basic", [
                "origin": ["location": ["latLng": ["latitude": origin.latitude, "longitude": origin.longitude]]],
                "destination": ["location": ["latLng": ["latitude": destination.latitude, "longitude": destination.longitude]]],
                "travelMode": "DRIVE",
                "routingPreference": "TRAFFIC_AWARE",
                "languageCode": lang,
                "units": "METRIC",
                "polylineQuality": "HIGH_QUALITY"
            ])
        ]

        for (label, body) in requests {
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { continue }

            var request = URLRequest(url: Self.endpoint)
            request.httpMethod = "POST"
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
            request.setValue(Self.fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")

            var delayNs: UInt64 = 100_000_000

            for attempt in 0..<3 {
                do {
                    let (data, response) = try await session.data(for: request)
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    guard statusCode == 200 else {
                        let responseBody = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                        print("[DirectionsClient] HTTP \(statusCode) from Routes API [\(label)] (attempt \(attempt + 1)): \(responseBody)")
                        // 400 = bad request — retrying the same body won't help; break to try next variant.
                        if statusCode == 400 { break }
                        if attempt < 2 { try? await Task.sleep(nanoseconds: delayNs); delayNs *= 2 }
                        continue
                    }
                    let dto = try JSONDecoder().decode(RoutesResponse.self, from: data)
                    guard let route = dto.routes.first,
                          let leg = route.legs.first else {
                        print("[DirectionsClient] Routes API returned no routes. " +
                              "Common causes: API key missing Routes API permission in Cloud Console; " +
                              "billing not enabled; no route between points.")
                        return DirectionsResult(points: [], steps: [], totalDurationSeconds: 0, distanceKm: 0)
                    }

                    var legPoints: [Coordinate2D] = []
                    if let encoded = leg.polyline?.encodedPolyline {
                        legPoints = PolylineDecoder.decode(encoded)
                    }
                    if legPoints.isEmpty {
                        for step in leg.steps {
                            if let encoded = step.polyline?.encodedPolyline {
                                legPoints.append(contentsOf: PolylineDecoder.decode(encoded))
                            }
                        }
                    }
                    if legPoints.isEmpty, let encoded = route.polyline?.encodedPolyline {
                        legPoints = PolylineDecoder.decode(encoded)
                    }

                    // Traffic segments are only present in the full request variant.
                    let trafficSegments = buildTrafficSegments(
                        from: leg.travelAdvisory?.speedReadingIntervals ?? [],
                        polylinePoints: legPoints
                    )

                    let steps = leg.steps.compactMap { step -> NavigationStep? in
                        guard let nav = step.navigationInstruction else { return nil }
                        return NavigationStep(
                            instruction: nav.instructions,
                            distanceMeters: step.distanceMeters ?? 0,
                            durationSeconds: parseDurationSeconds(step.staticDuration),
                            endLat: step.endLocation?.latLng?.latitude ?? 0,
                            endLng: step.endLocation?.latLng?.longitude ?? 0,
                            maneuver: nav.maneuver
                        )
                    }

                    return DirectionsResult(
                        points: legPoints,
                        steps: steps,
                        totalDurationSeconds: parseDurationSeconds(leg.duration),
                        distanceKm: Double(leg.distanceMeters ?? 0) / 1000.0,
                        trafficSegments: trafficSegments
                    )
                } catch {
                    print("[DirectionsClient] Request error [\(label)] (attempt \(attempt + 1)): \(error)")
                    if attempt < 2 { try? await Task.sleep(nanoseconds: delayNs); delayNs *= 2 }
                }
            }

        }

        print("[DirectionsClient] Google Routes API exhausted. Falling back to OSRM.")
        return await fetchOSRM(origin: origin, destination: destination)
    }

    // MARK: - OSRM fallback

    // ⚠️ PRODUCTION WARNING: routing.openstreetmap.de is a public demo server with
    // strict rate limits and a Terms of Service that prohibits production use.
    // Replace this with a self-hosted OSRM instance or a commercial routing API
    // (e.g. Mapbox Directions) before going live.
    func fetchOSRM(origin: LatLng, destination: LatLng) async -> DirectionsResult {
        print("[DirectionsClient] ⚠️ Using public OSRM demo server — not suitable for production traffic.")
        let urlString = "https://routing.openstreetmap.de/routed-car/route/v1/driving/" +
            "\(origin.longitude),\(origin.latitude);" +
            "\(destination.longitude),\(destination.latitude)" +
            "?overview=full&geometries=polyline&steps=true"

        guard let url = URL(string: urlString) else {
            return straightLineFallback(origin: origin, destination: destination)
        }

        do {
            let (data, response) = try await session.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard statusCode == 200 else {
                print("[DirectionsClient] OSRM HTTP \(statusCode)")
                return straightLineFallback(origin: origin, destination: destination)
            }

            let dto = try JSONDecoder().decode(OSRMResponse.self, from: data)
            guard let route = dto.routes.first else {
                return straightLineFallback(origin: origin, destination: destination)
            }

            let points = PolylineDecoder.decode(route.geometry)
            let distanceKm = (route.distance ?? 0) / 1000.0
            let durationSeconds = Int(route.duration ?? 0)

            let steps: [NavigationStep] = (route.legs?.first?.steps ?? []).compactMap { step in
                guard let maneuver = step.maneuver, let instruction = maneuver.instruction,
                      !instruction.isEmpty else { return nil }
                return NavigationStep(
                    instruction: instruction,
                    distanceMeters: Int(step.distance ?? 0),
                    durationSeconds: Int(step.duration ?? 0),
                    endLat: maneuver.location?.last ?? 0,
                    endLng: maneuver.location?.first ?? 0,
                    maneuver: maneuver.type
                )
            }

            print("[DirectionsClient] OSRM OK — \(points.count) points, \(steps.count) steps")
            return DirectionsResult(
                points: points.isEmpty ? [
                    Coordinate2D(latitude: origin.latitude, longitude: origin.longitude),
                    Coordinate2D(latitude: destination.latitude, longitude: destination.longitude)
                ] : points,
                steps: steps,
                totalDurationSeconds: durationSeconds > 0 ? durationSeconds : Int(distanceKm / 13.9 * 3600),
                distanceKm: distanceKm > 0 ? distanceKm : haversine(origin, destination)
            )
        } catch {
            print("[DirectionsClient] OSRM error: \(error)")
            return straightLineFallback(origin: origin, destination: destination)
        }
    }

    private func straightLineFallback(origin: LatLng, destination: LatLng) -> DirectionsResult {
        let distance = haversine(origin, destination)
        return DirectionsResult(
            points: [
                Coordinate2D(latitude: origin.latitude, longitude: origin.longitude),
                Coordinate2D(latitude: destination.latitude, longitude: destination.longitude)
            ],
            steps: [],
            totalDurationSeconds: Int(distance / 13.9 * 3600),
            distanceKm: distance
        )
    }

    // MARK: - Traffic segments

    private func buildTrafficSegments(
        from intervals: [SpeedReadingInterval],
        polylinePoints: [Coordinate2D]
    ) -> [TrafficSegment] {
        guard polylinePoints.count >= 2, !intervals.isEmpty else { return [] }
        var segments: [TrafficSegment] = []
        for interval in intervals {
            let start = max(0, interval.startPolylinePointIndex ?? 0)
            let end   = min(polylinePoints.count - 1, interval.endPolylinePointIndex)
            guard end > start else { continue }
            guard let speed = TrafficSpeed(rawValue: interval.speed) else { continue }
            let pts = Array(polylinePoints[start...end])
            guard pts.count >= 2 else { continue }
            segments.append(TrafficSegment(points: pts, speed: speed))
        }
        return segments
    }

    // MARK: - Helpers

    /// Parses duration strings like "123s" returned by the Routes API.
    private func parseDurationSeconds(_ value: String?) -> Int {
        guard let value, value.hasSuffix("s"),
              let seconds = Int(value.dropLast()) else { return 0 }
        return seconds
    }

    private func haversine(_ from: LatLng, _ to: LatLng) -> Double {
        let earthRadiusKm = 6371.0
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
            sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusKm * c
    }
}

// MARK: - DTOs (OSRM)

private struct OSRMResponse: Decodable {
    let routes: [OSRMRoute]
}

private struct OSRMRoute: Decodable {
    let geometry: String
    let distance: Double?
    let duration: Double?
    let legs: [OSRMLeg]?
}

private struct OSRMLeg: Decodable {
    let steps: [OSRMStep]?
}

private struct OSRMStep: Decodable {
    let distance: Double?
    let duration: Double?
    let maneuver: OSRMManeuver?
}

private struct OSRMManeuver: Decodable {
    let instruction: String?
    let type: String?
    // [longitude, latitude]
    let location: [Double]?
}

// MARK: - DTOs (Routes API v2)

private struct RoutesResponse: Decodable {
    let routes: [Route]
}

private struct Route: Decodable {
    let legs: [Leg]
    let polyline: EncodedPolyline?
}

private struct Leg: Decodable {
    let distanceMeters: Int?
    let duration: String?
    let polyline: EncodedPolyline?
    let travelAdvisory: LegTravelAdvisory?
    let steps: [Step]
}

private struct LegTravelAdvisory: Decodable {
    let speedReadingIntervals: [SpeedReadingInterval]?
}

private struct SpeedReadingInterval: Decodable {
    let startPolylinePointIndex: Int?
    let endPolylinePointIndex: Int
    let speed: String
}

private struct Step: Decodable {
    let distanceMeters: Int?
    let staticDuration: String?
    let endLocation: StepLocation?
    let polyline: EncodedPolyline?
    let navigationInstruction: NavigationInstruction?
}

private struct EncodedPolyline: Decodable {
    let encodedPolyline: String
}

private struct StepLocation: Decodable {
    let latLng: StepLatLng?
}

private struct StepLatLng: Decodable {
    let latitude: Double
    let longitude: Double
}

private struct NavigationInstruction: Decodable {
    let maneuver: String?
    let instructions: String
}
