import Foundation
import Combine

final class NavigationSessionManager: ObservableObject {
    struct Snapshot {
        let routePoints: [Coordinate2D]
        let trafficSegments: [TrafficSegment]
        let steps: [NavigationStep]
        let currentStepIndex: Int
        let currentStep: NavigationStep?
        let distanceToNextTurnM: Int
        let etaSeconds: Int
        let distanceKm: Double
        let snappedDriverLocation: LatLng?

        static var empty: Snapshot {
            Snapshot(
                routePoints: [],
                trafficSegments: [],
                steps: [],
                currentStepIndex: 0,
                currentStep: nil,
                distanceToNextTurnM: 0,
                etaSeconds: 0,
                distanceKm: 0,
                snappedDriverLocation: nil
            )
        }
    }

    enum Event {
        case rerouted(points: Int, steps: Int)
        case offRoute
    }

    @Published private(set) var snapshot: Snapshot = .empty
    let events = PassthroughSubject<Event, Never>()

    private let directionsClient: DirectionsClient
    private var target: LatLng?
    private var offRouteCounter = 0
    private var currentRideId: String?
    private let offRouteThresholdMeters: Double
    private var recentSpeeds: [Double] = []
    private var routeTask: Task<Void, Never>?
    private var rerouteTask: Task<Void, Never>?

    init(directionsClient: DirectionsClient, offRouteThresholdMeters: Double = 55.0) {
        self.directionsClient = directionsClient
        self.offRouteThresholdMeters = offRouteThresholdMeters
    }

    /// Placeholder instruction that respects the active app language.
    private var followRouteInstruction: String {
        switch UserDefaults.standard.string(forKey: "app_language") ?? "nl" {
        case "en": return "Follow the route to the destination"
        case "de": return "Der Route zum Ziel folgen"
        case "fr": return "Suivre l'itinéraire vers la destination"
        default:   return "Volg de route naar de bestemming"
        }
    }

    func fetchRoute(from origin: LatLng, to destination: LatLng) async -> DirectionsResult {
        await directionsClient.fetch(origin: origin, destination: destination)
    }

    func stop() {
        routeTask?.cancel()
        rerouteTask?.cancel()
        routeTask = nil
        rerouteTask = nil
        snapshot = .empty
        target = nil
        currentRideId = nil
        offRouteCounter = 0
        recentSpeeds.removeAll()
    }

    func startNewRoute(origin: LatLng, target: LatLng, onRouteLoaded: @escaping (DirectionsResult) -> Void) {
        self.target = target
        recentSpeeds.removeAll()
        routeTask?.cancel()

        // Publish a straight-line placeholder immediately so the map shows a
        // route and the "calculating" banner disappears before the async fetch
        // returns. The real route replaces this once the API responds.
        let placeholderInstruction = followRouteInstruction
        let placeholderPoints = [
            Coordinate2D(latitude: origin.latitude, longitude: origin.longitude),
            Coordinate2D(latitude: target.latitude, longitude: target.longitude)
        ]
        let placeholderEta = Int(haversineKm(origin, target) / 13.9 * 3600)
        let placeholderStep = NavigationStep(
            instruction: placeholderInstruction,
            distanceMeters: Int(haversineKm(origin, target) * 1000),
            durationSeconds: placeholderEta,
            endLat: target.latitude,
            endLng: target.longitude,
            maneuver: nil
        )
        snapshot = Snapshot(
            routePoints: placeholderPoints,
            trafficSegments: [],
            steps: [placeholderStep],
            currentStepIndex: 0,
            currentStep: placeholderStep,
            distanceToNextTurnM: Int(haversineKm(origin, target) * 1000),
            etaSeconds: placeholderEta,
            distanceKm: haversineKm(origin, target),
            snappedDriverLocation: nil
        )
        offRouteCounter = 0

        routeTask = Task { [weak self] in
            guard let self else { return }
            let result = await directionsClient.fetch(origin: origin, destination: target)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                // When the API fails (empty points), fall back to a straight-line route so the
                // loading banner always resolves rather than spinning forever.
                let resolvedPoints: [Coordinate2D] = result.points.isEmpty ? [
                    Coordinate2D(latitude: origin.latitude, longitude: origin.longitude),
                    Coordinate2D(latitude: target.latitude, longitude: target.longitude)
                ] : result.points

                let distanceKm = result.distanceKm > 0 ? result.distanceKm : self.haversineKm(origin, target)
                let etaSeconds = result.totalDurationSeconds > 0
                    ? result.totalDurationSeconds
                    : Int(distanceKm / 13.9 * 3600)

                // When there are no turn-by-turn steps (API failure or no key), provide a
                // single catch-all step so navigationStep is always populated in the view.
                let fallbackInstruction = self.followRouteInstruction
                let resolvedSteps: [NavigationStep] = result.steps.isEmpty ? [
                    NavigationStep(
                        instruction: fallbackInstruction,
                        distanceMeters: Int(distanceKm * 1000),
                        durationSeconds: etaSeconds,
                        endLat: target.latitude,
                        endLng: target.longitude,
                        maneuver: nil
                    )
                ] : result.steps

                self.snapshot = Snapshot(
                    routePoints: resolvedPoints,
                    trafficSegments: result.trafficSegments,
                    steps: resolvedSteps,
                    currentStepIndex: 0,
                    currentStep: resolvedSteps.first,
                    distanceToNextTurnM: resolvedSteps.first?.distanceMeters ?? 0,
                    etaSeconds: etaSeconds,
                    distanceKm: distanceKm,
                    snappedDriverLocation: nil
                )
                self.offRouteCounter = 0
                onRouteLoaded(result)
            }
        }
    }

    func onLocation(_ rideId: String, update: DriverLocationUpdate, onReroute: @escaping (DirectionsResult) -> Void = { _ in }) {
        currentRideId = rideId
        guard let target = target else { return }
        guard snapshot.routePoints.count >= 2 else { return }

        recentSpeeds.append(update.speedKmh)
        if recentSpeeds.count > 5 { recentSpeeds.removeFirst() }

        let snapped = snapToPolyline(point: update.latLng, polyline: snapshot.routePoints)
        let distanceToLine = snapped.distance
        let snappedPoint = snapped.point

        var stepIndex = snapshot.currentStepIndex
        var distanceToNextTurn = snapshot.distanceToNextTurnM
        let steps = snapshot.steps
        if let step = steps[safe: stepIndex] {
            let stepEnd = LatLng(latitude: step.endLat, longitude: step.endLng)
            let distToEnd = Int(haversineKm(snappedPoint, stepEnd) * 1000)
            distanceToNextTurn = distToEnd
            // Advance the step earlier at higher speeds so the next instruction
            // is ready well before the driver reaches the manoeuvre point.
            // Formula: clamp(speed_kmh * 0.6, 20…80) metres.
            let advanceThreshold = Int(min(80, max(20, update.speedKmh * 0.6)))
            if distToEnd < advanceThreshold, stepIndex < steps.count - 1 {
                stepIndex += 1
                distanceToNextTurn = steps[stepIndex].distanceMeters
            }
        }

        let newSnapshot = Snapshot(
            routePoints: snapshot.routePoints,
            trafficSegments: snapshot.trafficSegments,
            steps: steps,
            currentStepIndex: stepIndex,
            currentStep: steps[safe: stepIndex],
            distanceToNextTurnM: distanceToNextTurn,
            etaSeconds: computeEtaSeconds(
                remainingMeters: distanceRemaining(from: snappedPoint, steps: steps, stepIndex: stepIndex),
                speedKmh: update.speedKmh,
                trafficSegments: snapshot.trafficSegments,
                snappedPosition: snappedPoint
            ),
            distanceKm: snapshot.distanceKm,
            snappedDriverLocation: snappedPoint
        )
        snapshot = newSnapshot

        // Require 4 consecutive off-route samples before rerouting, and only
        // reroute when the driver is actually moving (>5 km/h). This prevents
        // unnecessary reroutes caused by GPS drift while stopped in traffic or
        // at a red light, and reduces false positives on tight urban geometry.
        if distanceToLine > offRouteThresholdMeters && update.speedKmh > 5.0 {
            offRouteCounter += 1
            if offRouteCounter >= 4 {
                offRouteCounter = 0
                events.send(.offRoute)
                rerouteTask?.cancel()
                rerouteTask = Task { [weak self] in
                    guard let self else { return }
                    let res = await directionsClient.fetch(origin: snappedPoint, destination: target)
                    guard !res.points.isEmpty, !Task.isCancelled else { return }
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.events.send(.rerouted(points: res.points.count, steps: res.steps.count))
                        self.snapshot = Snapshot(
                            routePoints: res.points,
                            trafficSegments: res.trafficSegments,
                            steps: res.steps,
                            currentStepIndex: 0,
                            currentStep: res.steps.first,
                            distanceToNextTurnM: res.steps.first?.distanceMeters ?? 0,
                            etaSeconds: res.totalDurationSeconds,
                            distanceKm: res.distanceKm,
                            snappedDriverLocation: snappedPoint
                        )
                        onReroute(res)
                    }
                }
            }
        } else {
            offRouteCounter = 0
        }
    }

    private func snapToPolyline(point: LatLng, polyline: [Coordinate2D]) -> (point: LatLng, distance: Double) {
        var minDist = Double.greatestFiniteMagnitude
        var closest = point
        for i in 0..<(polyline.count - 1) {
            let a = LatLng(latitude: polyline[i].latitude, longitude: polyline[i].longitude)
            let b = LatLng(latitude: polyline[i + 1].latitude, longitude: polyline[i + 1].longitude)
            let candidate = closestPointOnSegment(p: point, a: a, b: b)
            let dist = haversineKm(point, candidate) * 1000
            if dist < minDist {
                minDist = dist
                closest = candidate
            }
        }
        return (closest, minDist)
    }

    private func closestPointOnSegment(p: LatLng, a: LatLng, b: LatLng) -> LatLng {
        let ax = a.longitude
        let ay = a.latitude
        let bx = b.longitude
        let by = b.latitude
        let px = p.longitude
        let py = p.latitude

        let abx = bx - ax
        let aby = by - ay
        let apx = px - ax
        let apy = py - ay
        let ab2 = abx * abx + aby * aby
        let t = ab2 == 0 ? 0 : max(0, min(1, ((apx * abx + apy * aby) / ab2)))
        return LatLng(latitude: ay + t * aby, longitude: ax + t * abx)
    }

    /// Returns the estimated remaining trip distance in metres using step data.
    /// This correctly honours the current step index: it measures from `from`
    /// to the end of the current step, then sums all subsequent step distances.
    private func distanceRemaining(from: LatLng, steps: [NavigationStep], stepIndex: Int) -> Int {
        guard !steps.isEmpty else { return 0 }
        var meters = 0.0
        if let currentStep = steps[safe: stepIndex] {
            let stepEnd = LatLng(latitude: currentStep.endLat, longitude: currentStep.endLng)
            meters = haversineKm(from, stepEnd) * 1000
        }
        for i in (stepIndex + 1)..<steps.count {
            meters += Double(steps[i].distanceMeters)
        }
        return Int(meters)
    }

    private func computeEtaSeconds(
        remainingMeters: Int,
        speedKmh: Double,
        trafficSegments: [TrafficSegment] = [],
        snappedPosition: LatLng? = nil
    ) -> Int {
        let avg = recentSpeeds.isEmpty ? speedKmh : recentSpeeds.reduce(0, +) / Double(recentSpeeds.count)

        // When moving (> 5 km/h), live GPS speed is the most accurate signal.
        guard avg < 5.0, !trafficSegments.isEmpty, let pos = snappedPosition else {
            let speedMps = max(avg, 3.0) / 3.6
            return max(Int(Double(remainingMeters) / speedMps), 0)
        }

        // Driver is slow or stopped — walk remaining traffic segments to produce
        // a traffic-aware estimate rather than extrapolating crawl-speed GPS.
        var startSegIdx = 0
        var minDist = Double.greatestFiniteMagnitude
        for (i, seg) in trafficSegments.enumerated() {
            if let first = seg.points.first {
                let d = haversineKm(pos, LatLng(latitude: first.latitude, longitude: first.longitude))
                if d < minDist { minDist = d; startSegIdx = i }
            }
        }

        var etaSeconds = 0.0
        var coveredMeters = 0.0
        for i in startSegIdx..<trafficSegments.count {
            let seg = trafficSegments[i]
            var segMeters = 0.0
            for j in 0..<(seg.points.count - 1) {
                segMeters += haversineKm(
                    LatLng(latitude: seg.points[j].latitude,     longitude: seg.points[j].longitude),
                    LatLng(latitude: seg.points[j + 1].latitude, longitude: seg.points[j + 1].longitude)
                ) * 1000
            }
            let applicable = min(segMeters, Double(remainingMeters) - coveredMeters)
            guard applicable > 0 else { break }
            etaSeconds += applicable / trafficSpeedMps(seg.speed)
            coveredMeters += applicable
            if coveredMeters >= Double(remainingMeters) { break }
        }

        // Segments may not cover the full remaining distance (e.g. no traffic data
        // for the tail of the route). Top up using normal-traffic speed.
        if coveredMeters < Double(remainingMeters) {
            etaSeconds += (Double(remainingMeters) - coveredMeters) / trafficSpeedMps(.normal)
        }

        return max(Int(etaSeconds), 0)
    }

    /// Reference speeds per Google traffic classification used for ETA estimates
    /// when the driver's GPS speed is unreliable (stationary / near-zero).
    private func trafficSpeedMps(_ speed: TrafficSpeed) -> Double {
        switch speed {
        case .normal:     return 13.0  // ~47 km/h — typical urban flow
        case .slow:       return  6.0  // ~22 km/h — congested
        case .trafficJam: return  2.0  // ~7 km/h  — near standstill
        }
    }

    private func haversineKm(_ from: LatLng, _ to: LatLng) -> Double {
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
