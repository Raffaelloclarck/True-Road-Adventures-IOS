import SwiftUI
import CoreLocation
import GoogleMaps

// MARK: - Google Maps UIViewRepresentable

struct TRAGoogleMapView: UIViewRepresentable {
    var pickup: LatLng?
    var destination: LatLng?
    var driverLocation: LatLng?
    var customerLocation: LatLng?
    /// Rider/driver's own GPS position — used to centre the home-screen map
    /// before any ride is active (pickup & destination are nil).
    var userLocation: LatLng?
    var routePoints: [Coordinate2D]
    var trafficSegments: [TrafficSegment] = []
    var bearing: Double
    var speedKmh: Double
    var followDriver: Bool
    var showTraffic: Bool
    var onUserPanned: () -> Void
    /// Measured height of bottom UI (sheet / pill) — offsets the nav camera so the driver marker stays visible.
    var bottomInset: CGFloat = 0
    /// Distance to the next turn in metres — drives approach zoom.
    var distanceToNextTurnM: Int = 0
    /// When this value changes the coordinator resets its camera-fitting state
    /// so the map re-centres for the new ride context. Avoids destroying and
    /// recreating the GMSMapView (which spawns duplicate CCTClearcutUploaders).
    var cameraResetKey: String = ""

    // MARK: Night mode

    private static var isNightTime: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 20 || hour < 6
    }

    // Standard Google Maps night-mode style
    private static let nightMapStyle = """
    [{"elementType":"geometry","stylers":[{"color":"#1d2c3b"}]},
     {"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},
     {"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},
     {"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a57"}]},
     {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#255763"}]},
     {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},
     {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2c6675"}]},
     {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#255763"}]},
     {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#b0d5ce"}]},
     {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]},
     {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#1e3231"}]},
     {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f3948"}]}]
    """

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(
            target: CLLocationCoordinate2D(latitude: 5.8520, longitude: -55.2038),
            zoom: 12
        )
        let mapView = GMSMapView(options: options)
        mapView.isTrafficEnabled = showTraffic
        mapView.settings.compassButton = true
        mapView.settings.zoomGestures = true
        mapView.settings.scrollGestures = true
        mapView.settings.myLocationButton = false
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView
        // Apply day/night map style on first render
        context.coordinator.applyMapStyle(mapView, dark: TRAGoogleMapView.isNightTime)
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        let c = context.coordinator
        c.parent = self

        if cameraResetKey != c.lastCameraResetKey {
            c.initialBoundsSet = false
            c.routeBoundsFitted = false
            c.lastCameraResetKey = cameraResetKey
        }

        mapView.isTrafficEnabled = showTraffic

        // Transition day ↔ night style when the hour crosses the threshold.
        let dark = TRAGoogleMapView.isNightTime
        if dark != c.isDarkMode {
            c.applyMapStyle(mapView, dark: dark)
        }

        // During navigation offset the camera so the driver arrow sits above the bottom overlay.
        // Prefer measured `bottomInset`; until layout completes, fall back to 30 % of screen height.
        let screenH = mapView.window?.windowScene?.screen.bounds.height ?? mapView.bounds.height
        let inset = bottomInset > 0 ? bottomInset : screenH * 0.30
        let targetPadding: UIEdgeInsets = followDriver
            ? UIEdgeInsets(top: 0, left: 0, bottom: inset, right: 0)
            : .zero
        if mapView.padding != targetPadding {
            mapView.padding = targetPadding
        }

        c.updatePolyline(on: mapView)
        c.updateMarkers(on: mapView)
        c.updateCamera(on: mapView)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: TRAGoogleMapView
        weak var mapView: GMSMapView?

        private var routePolylines: [GMSPolyline] = []
        private var pickupMarker: GMSMarker?
        private var destinationMarker: GMSMarker?
        private var driverMarker: GMSMarker?
        private var customerMarker: GMSMarker?
        private var driverArrowImage: UIImage?

        var initialBoundsSet = false
        var routeBoundsFitted = false
        fileprivate var lastCameraResetKey: String = ""
        fileprivate var isDarkMode: Bool = false

        init(_ parent: TRAGoogleMapView) {
            self.parent = parent
        }

        // MARK: Night mode

        func applyMapStyle(_ mapView: GMSMapView, dark: Bool) {
            isDarkMode = dark
            if dark, let style = try? GMSMapStyle(jsonString: TRAGoogleMapView.nightMapStyle) {
                mapView.mapStyle = style
            } else {
                mapView.mapStyle = nil
            }
        }

        // MARK: Polyline

        /// White outline + coloured stroke so the route reads as one path on the basemap.
        private func appendOutlinedPolyline(path: GMSMutablePath, strokeColor: UIColor, on mapView: GMSMapView) {
            let border = GMSPolyline(path: path)
            border.strokeWidth = 12
            border.strokeColor = .white
            border.geodesic = true
            border.map = mapView
            routePolylines.append(border)

            let line = GMSPolyline(path: path)
            line.strokeWidth = 8
            line.strokeColor = strokeColor
            line.geodesic = true
            line.map = mapView
            routePolylines.append(line)
        }

        private func closestRouteIndex(to coord: Coordinate2D, in route: [Coordinate2D]) -> Int {
            let from = LatLng(latitude: coord.latitude, longitude: coord.longitude)
            var bestI = 0
            var bestD = Double.greatestFiniteMagnitude
            for (i, pt) in route.enumerated() {
                let d = haversineM(from, LatLng(latitude: pt.latitude, longitude: pt.longitude))
                if d < bestD {
                    bestD = d
                    bestI = i
                }
            }
            return bestI
        }

        /// Drop vertices that lie entirely before the driver on the decoded polyline (traffic segment path).
        private func trimTrafficSegment(_ seg: TrafficSegment, routePoints: [Coordinate2D], startRouteIndex: Int) -> TrafficSegment? {
            guard !seg.points.isEmpty, !routePoints.isEmpty else { return nil }
            guard startRouteIndex > 0 else { return seg }

            var firstKeep: Int?
            for (j, p) in seg.points.enumerated() {
                if closestRouteIndex(to: p, in: routePoints) >= startRouteIndex {
                    firstKeep = j
                    break
                }
            }
            guard let fk = firstKeep else { return nil }

            var trimmed = Array(seg.points[fk...])
            if trimmed.count < 2 {
                if fk > 0 {
                    trimmed = [seg.points[fk - 1], seg.points[fk]]
                } else if fk + 1 < seg.points.count {
                    trimmed = [seg.points[fk], seg.points[fk + 1]]
                } else {
                    return nil
                }
            }
            return TrafficSegment(points: trimmed, speed: seg.speed)
        }

        func updatePolyline(on mapView: GMSMapView) {
            routePolylines.forEach { $0.map = nil }
            routePolylines.removeAll()

            if parent.routePoints.count >= 2 {
                var routeStartIdx = 0
                var displayPoints = parent.routePoints
                if parent.followDriver, let drv = parent.driverLocation {
                    var minDist = Double.greatestFiniteMagnitude
                    var startIdx = 0
                    for (i, pt) in parent.routePoints.enumerated() {
                        let d = haversineM(drv, LatLng(latitude: pt.latitude, longitude: pt.longitude))
                        if d < minDist { minDist = d; startIdx = i }
                    }
                    routeStartIdx = startIdx
                    if startIdx > 0 {
                        displayPoints = Array(parent.routePoints[startIdx...])
                    }
                }

                if !parent.trafficSegments.isEmpty {
                    let segmentsToDraw: [TrafficSegment]
                    if parent.followDriver, parent.driverLocation != nil {
                        segmentsToDraw = parent.trafficSegments.compactMap {
                            trimTrafficSegment($0, routePoints: parent.routePoints, startRouteIndex: routeStartIdx)
                        }
                    } else {
                        segmentsToDraw = parent.trafficSegments
                    }
                    for segment in segmentsToDraw where segment.points.count >= 2 {
                        let path = GMSMutablePath()
                        for pt in segment.points {
                            path.add(CLLocationCoordinate2D(latitude: pt.latitude, longitude: pt.longitude))
                        }
                        appendOutlinedPolyline(path: path, strokeColor: segment.speed.strokeColor, on: mapView)
                    }
                } else if displayPoints.count >= 2 {
                    let path = GMSMutablePath()
                    for pt in displayPoints {
                        path.add(CLLocationCoordinate2D(latitude: pt.latitude, longitude: pt.longitude))
                    }
                    let teal = UIColor(red: 0x00 / 255, green: 0xC9 / 255, blue: 0xA7 / 255, alpha: 1)
                    appendOutlinedPolyline(path: path, strokeColor: teal, on: mapView)
                }

                if !parent.followDriver && !routeBoundsFitted {
                    routeBoundsFitted = true
                    let firstPath = GMSMutablePath()
                    for pt in parent.routePoints { firstPath.add(CLLocationCoordinate2D(latitude: pt.latitude, longitude: pt.longitude)) }
                    var bounds = GMSCoordinateBounds(path: firstPath)
                    if let p = parent.pickup {
                        bounds = bounds.includingCoordinate(
                            CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
                        )
                    }
                    if let d = parent.destination {
                        bounds = bounds.includingCoordinate(
                            CLLocationCoordinate2D(latitude: d.latitude, longitude: d.longitude)
                        )
                    }
                    mapView.moveCamera(GMSCameraUpdate.fit(bounds, withPadding: 60))
                }
            } else {
                // Fallback line from driver to pickup (or pickup to destination)
                let start = parent.driverLocation ?? parent.pickup
                let end = parent.driverLocation != nil ? parent.pickup : parent.destination
                if let s = start, let e = end {
                    let path = GMSMutablePath()
                    path.add(CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude))
                    path.add(CLLocationCoordinate2D(latitude: e.latitude, longitude: e.longitude))
                    let dimTeal = UIColor(red: 0x00 / 255, green: 0xC9 / 255, blue: 0xA7 / 255, alpha: 0.4)
                    appendOutlinedPolyline(path: path, strokeColor: dimTeal, on: mapView)
                }
            }
        }

        // MARK: Camera

        // Tracking state for debounce + bearing smoothing
        private var lastCameraLat: Double = 0
        private var lastCameraLng: Double = 0
        private var smoothBearing: Double = 0
        private var wasFollowing: Bool = false

        func updateCamera(on mapView: GMSMapView) {
            if parent.followDriver, let loc = parent.driverLocation {
                // ── Adaptive bearing smoothing (EMA) ──────────────────────────
                // Use a higher alpha when the bearing is changing rapidly (real
                // turn) vs. nearly constant (GPS noise while driving straight).
                let rawBearing = parent.bearing
                let bearingChange = abs(angleDiff(rawBearing, smoothBearing))
                let alpha: Double
                switch parent.speedKmh {
                case ..<3:
                    alpha = 0.05                    // nearly stationary — suppress all noise
                case ..<20:
                    alpha = bearingChange > 20 ? 0.40 : 0.15   // slow — responsive on turns
                default:
                    alpha = bearingChange > 15 ? 0.50 : 0.30   // highway — fast on turns, smooth on straights
                }
                smoothBearing = lerpAngle(smoothBearing, rawBearing, alpha: alpha)

                // ── Look-ahead offset ─────────────────────────────────────────
                // Scale look-ahead with speed so the driver sees further ahead
                // at highway speeds (Google Maps uses ~400 m on motorways).
                let lookAheadMeters: Double
                switch parent.speedKmh {
                case ..<3:   lookAheadMeters = 0    // stationary — centre on driver
                case ..<10:  lookAheadMeters = 20
                case ..<20:  lookAheadMeters = 100
                case ..<50:  lookAheadMeters = 180
                case ..<90:  lookAheadMeters = 280
                default:     lookAheadMeters = 400
                }
                let cameraTarget = lookAheadPoint(
                    from: loc,
                    bearing: smoothBearing,
                    routePoints: parent.routePoints,
                    distance: lookAheadMeters
                )

                // ── Debounce ──────────────────────────────────────────────────
                let moved = haversineM(
                    LatLng(latitude: lastCameraLat, longitude: lastCameraLng),
                    LatLng(latitude: cameraTarget.latitude, longitude: cameraTarget.longitude)
                )
                let bearingDelta = abs(angleDiff(smoothBearing, mapView.camera.bearing))
                let followJustEnabled = parent.followDriver && !wasFollowing
                wasFollowing = parent.followDriver

                guard moved > 3 || bearingDelta > 3 || followJustEnabled else { return }
                lastCameraLat = cameraTarget.latitude
                lastCameraLng = cameraTarget.longitude

                // ── Speed-based zoom & tilt ────────────────────────────────────
                let speedZoom: Float
                switch parent.speedKmh {
                case ..<5:   speedZoom = 19.5   // near-standstill / intersection
                case ..<20:  speedZoom = 19
                case ..<50:  speedZoom = 18.5
                case ..<90:  speedZoom = 18
                default:     speedZoom = 17
                }

                // ── Approach zoom — zoom IN when a turn is close ───────────────
                // distanceToNextTurnM tells us how close the next manoeuvre is.
                // We take the maximum of speed-zoom and approach-zoom so we
                // never zoom OUT during an approach.
                let approachZoom: Float
                switch parent.distanceToNextTurnM {
                case 1..<30:    approachZoom = 20.5
                case 30..<80:   approachZoom = 20
                case 80..<150:  approachZoom = 19.5
                case 150..<300: approachZoom = 19
                default:        approachZoom = speedZoom
                }
                let zoom = max(speedZoom, approachZoom)

                let tilt: Double
                switch parent.speedKmh {
                case ..<5:   tilt = 50
                case ..<20:  tilt = 55
                case ..<50:  tilt = 58
                case ..<90:  tilt = 65
                default:     tilt = 70
                }

                let camera = GMSCameraPosition(
                    target: cameraTarget,
                    zoom: zoom,
                    bearing: smoothBearing,
                    viewingAngle: tilt
                )

                // Always animate with an explicit duration so consecutive updates
                // (every ~1 s) form one fluid continuous sweep instead of choppy
                // 0.25 s snaps. First activation gets a cinematic 1.0 s sweep.
                CATransaction.begin()
                CATransaction.setValue(
                    followJustEnabled ? 1.0 : 0.85,
                    forKey: kCATransactionAnimationDuration
                )
                mapView.animate(to: camera)
                CATransaction.commit()

                driverMarker?.rotation = smoothBearing

            } else if !parent.followDriver {
                wasFollowing = false
                // Keep the arrow pointing the right direction even while the user
                // has panned away. Use the raw bearing (no camera EMA needed here).
                driverMarker?.rotation = parent.bearing
                if !initialBoundsSet {
                    if let pickup = parent.pickup, let dest = parent.destination {
                        initialBoundsSet = true
                        var bounds = GMSCoordinateBounds(
                            coordinate: CLLocationCoordinate2D(latitude: pickup.latitude, longitude: pickup.longitude),
                            coordinate: CLLocationCoordinate2D(latitude: dest.latitude, longitude: dest.longitude)
                        )
                        if let drv = parent.driverLocation {
                            bounds = bounds.includingCoordinate(
                                CLLocationCoordinate2D(latitude: drv.latitude, longitude: drv.longitude)
                            )
                        }
                        mapView.moveCamera(GMSCameraUpdate.fit(bounds, withPadding: 60))
                    } else if let dest = parent.destination {
                        // Destination-only (e.g. status = pickedUp — pickup already done).
                        // Fit the camera to driver + destination so the rider sees
                        // where they are headed rather than the full trip extent.
                        initialBoundsSet = true
                        var bounds = GMSCoordinateBounds(
                            coordinate: CLLocationCoordinate2D(latitude: dest.latitude, longitude: dest.longitude),
                            coordinate: CLLocationCoordinate2D(latitude: dest.latitude, longitude: dest.longitude)
                        )
                        if let drv = parent.driverLocation {
                            bounds = bounds.includingCoordinate(
                                CLLocationCoordinate2D(latitude: drv.latitude, longitude: drv.longitude)
                            )
                        }
                        mapView.moveCamera(GMSCameraUpdate.fit(bounds, withPadding: 80))
                    } else if let user = parent.userLocation {
                        // Home screen: no ride yet — centre on user's GPS location
                        initialBoundsSet = true
                        mapView.moveCamera(GMSCameraUpdate.setTarget(
                            CLLocationCoordinate2D(latitude: user.latitude, longitude: user.longitude),
                            zoom: 14
                        ))
                    }
                }
            } else {
                // followDriver=true but driverLocation is not yet available —
                // show pickup+destination as an interim view so the map is never
                // stuck on the default hardcoded position.
                guard !initialBoundsSet, let pickup = parent.pickup, let dest = parent.destination else { return }
                initialBoundsSet = true
                let bounds = GMSCoordinateBounds(
                    coordinate: CLLocationCoordinate2D(latitude: pickup.latitude, longitude: pickup.longitude),
                    coordinate: CLLocationCoordinate2D(latitude: dest.latitude, longitude: dest.longitude)
                )
                mapView.moveCamera(GMSCameraUpdate.fit(bounds, withPadding: 80))
            }
        }

        // ── Navigation geometry helpers ───────────────────────────────────────

        /// Walk `distance` metres forward along `routePoints` starting from the
        /// closest point on the polyline to `from`. Falls back to a simple
        /// geodesic projection when the polyline is empty.
        private func lookAheadPoint(
            from: LatLng,
            bearing: Double,
            routePoints: [Coordinate2D],
            distance: Double
        ) -> CLLocationCoordinate2D {
            guard routePoints.count >= 2 else {
                return geodesicProject(from: from, bearing: bearing, distanceM: distance)
            }

            // Find the closest polyline index to current driver position
            var minDist = Double.greatestFiniteMagnitude
            var startIdx = 0
            for (i, pt) in routePoints.enumerated() {
                let d = haversineM(from, LatLng(latitude: pt.latitude, longitude: pt.longitude))
                if d < minDist { minDist = d; startIdx = i }
            }

            // Walk forward `distance` metres from that index
            var remaining = distance
            for i in startIdx..<(routePoints.count - 1) {
                let a = LatLng(latitude: routePoints[i].latitude,     longitude: routePoints[i].longitude)
                let b = LatLng(latitude: routePoints[i + 1].latitude, longitude: routePoints[i + 1].longitude)
                let segLen = haversineM(a, b)
                if remaining <= segLen {
                    let t = remaining / segLen
                    return CLLocationCoordinate2D(
                        latitude:  a.latitude  + t * (b.latitude  - a.latitude),
                        longitude: a.longitude + t * (b.longitude - a.longitude)
                    )
                }
                remaining -= segLen
            }
            // Past the end of the polyline — return the last point
            let last = routePoints.last!
            return CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
        }

        /// Project a point `distanceM` metres in `bearing` direction (geodesic).
        private func geodesicProject(from: LatLng, bearing: Double, distanceM: Double) -> CLLocationCoordinate2D {
            let R = 6371000.0
            let d = distanceM / R
            let b = bearing * .pi / 180
            let lat1 = from.latitude * .pi / 180
            let lon1 = from.longitude * .pi / 180
            let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(b))
            let lon2 = lon1 + atan2(sin(b) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
            return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
        }

        private func haversineM(_ a: LatLng, _ b: LatLng) -> Double {
            let R = 6371000.0
            let dLat = (b.latitude  - a.latitude)  * .pi / 180
            let dLon = (b.longitude - a.longitude) * .pi / 180
            let lat1 = a.latitude * .pi / 180
            let lat2 = b.latitude * .pi / 180
            let x = sin(dLat / 2) * sin(dLat / 2) +
                    sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
            return R * 2 * atan2(sqrt(x), sqrt(1 - x))
        }

        /// Lerp between two compass angles across the 0/360 wrap boundary.
        private func lerpAngle(_ from: Double, _ to: Double, alpha: Double) -> Double {
            var diff = to - from
            if diff > 180  { diff -= 360 }
            if diff < -180 { diff += 360 }
            var result = from + diff * alpha
            if result < 0   { result += 360 }
            if result >= 360 { result -= 360 }
            return result
        }

        /// Smallest signed difference between two compass angles.
        private func angleDiff(_ a: Double, _ b: Double) -> Double {
            var d = a - b
            if d > 180  { d -= 360 }
            if d < -180 { d += 360 }
            return d
        }

        // MARK: Markers

        func updateMarkers(on mapView: GMSMapView) {
            updatePickupMarker(on: mapView)
            updateDestinationMarker(on: mapView)
            updateCustomerMarker(on: mapView)
            updateDriverMarker(on: mapView)
        }

        private func updatePickupMarker(on mapView: GMSMapView) {
            if let p = parent.pickup {
                if pickupMarker == nil {
                    let m = GMSMarker()
                    m.icon = GMSMarker.markerImage(with: UIColor(red: 0x00 / 255, green: 0xC9 / 255, blue: 0xA7 / 255, alpha: 1))
                    m.title = "Ophaallocatie"
                    m.map = mapView
                    pickupMarker = m
                }
                pickupMarker?.position = CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
            } else {
                pickupMarker?.map = nil
                pickupMarker = nil
            }
        }

        private func updateDestinationMarker(on mapView: GMSMapView) {
            if let d = parent.destination {
                if destinationMarker == nil {
                    let m = GMSMarker()
                    m.icon = GMSMarker.markerImage(with: UIColor(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255, alpha: 1))
                    m.title = "Bestemming"
                    m.map = mapView
                    destinationMarker = m
                }
                destinationMarker?.position = CLLocationCoordinate2D(latitude: d.latitude, longitude: d.longitude)
            } else {
                destinationMarker?.map = nil
                destinationMarker = nil
            }
        }

        private func updateCustomerMarker(on mapView: GMSMapView) {
            if let c = parent.customerLocation {
                if customerMarker == nil {
                    let m = GMSMarker()
                    m.icon = GMSMarker.markerImage(with: .orange)
                    m.title = "Klant (live)"
                    m.map = mapView
                    customerMarker = m
                }
                customerMarker?.position = CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
            } else {
                customerMarker?.map = nil
                customerMarker = nil
            }
        }

        private func updateDriverMarker(on mapView: GMSMapView) {
            if let loc = parent.driverLocation {
                if driverMarker == nil {
                    if driverArrowImage == nil {
                        driverArrowImage = makeDriverArrowImage()
                    }
                    let m = GMSMarker()
                    m.icon = driverArrowImage
                    m.isFlat = true
                    m.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                    m.title = "Chauffeur"
                    m.map = mapView
                    driverMarker = m
                }
                driverMarker?.position = CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
                // Rotation is managed exclusively by updateCamera using smoothBearing.
                // Setting raw parent.bearing here would override the smoothed value
                // and cause the arrow to jitter, especially when followDriver = false.
            } else {
                driverMarker?.map = nil
                driverMarker = nil
            }
        }

        private func makeDriverArrowImage(size: CGFloat = 64) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                let c = CGPoint(x: size / 2, y: size / 2)
                let r = size / 2 - 4

                // Drop shadow
                ctx.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.25).cgColor)
                ctx.cgContext.addArc(center: CGPoint(x: c.x + 2, y: c.y + 2),
                                     radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                ctx.cgContext.fillPath()

                // Teal circle
                ctx.cgContext.setFillColor(UIColor(red: 0x00 / 255, green: 0xC9 / 255, blue: 0xA7 / 255, alpha: 1).cgColor)
                ctx.cgContext.addArc(center: c, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                ctx.cgContext.fillPath()

                // White upward arrow
                let arrow = UIBezierPath()
                arrow.move(to: CGPoint(x: size / 2, y: 10))
                arrow.addLine(to: CGPoint(x: size - 14, y: size - 12))
                arrow.addLine(to: CGPoint(x: size / 2, y: size - 20))
                arrow.addLine(to: CGPoint(x: 14, y: size - 12))
                arrow.close()
                UIColor.white.setFill()
                arrow.fill()
            }
        }

        // MARK: GMSMapViewDelegate

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            if gesture {
                parent.onUserPanned()
            }
        }
    }
}

// MARK: - Traffic speed colour mapping

private extension TrafficSpeed {
    var strokeColor: UIColor {
        switch self {
        case .normal:
            return UIColor(red: 0x00 / 255, green: 0xC9 / 255, blue: 0xA7 / 255, alpha: 1)   // teal
        case .slow:
            return UIColor(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255, alpha: 1)   // amber
        case .trafficJam:
            return UIColor(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255, alpha: 1)   // red
        }
    }
}
