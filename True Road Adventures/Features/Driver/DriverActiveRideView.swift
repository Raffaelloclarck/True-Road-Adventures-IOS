import SwiftUI
import CoreLocation
import Combine
import AVFoundation

struct DriverActiveRideView: View {
    let ride: Ride

    @EnvironmentObject private var rideService: RideService
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    // Navigation state
    @State private var navigationStep: String?
    @State private var navigationManeuver: String?
    @State private var distanceToNextTurnM: Int = 0
    @State private var etaSeconds: Int?
    @State private var currentRoutePoints: [Coordinate2D] = []
    @State private var currentTrafficSegments: [TrafficSegment] = []
    @State private var snappedLocation: LatLng?
    @State private var gpsLocation: LatLng?
    @State private var navigationStarted = false
    @State private var isRerouting = false

    // Camera / map controls
    @State private var isFollowingDriver = true
    @State private var useHeadingUp = true
    @State private var currentBearing: Double = 0
    @State private var currentSpeedKmh: Double = 0

    // UI state
    @State private var isPanelExpanded = true
    @State private var showChat = false
    @State private var isMuted = false

    // Voice
    private let speechSynthesizer = AVSpeechSynthesizer()
    @State private var lastSpokenStep: String?

    // Pre-announcement tracking (Uber/Bolt style: 500m, 200m, at turn)
    @State private var lastAnnouncedStepIndex: Int = -1
    @State private var lastAnnouncedZone: String = ""

    // ETA Firestore sync throttle
    @State private var lastEtaWrite: Date?

    // Ride timing for fare calculation
    @State private var pickedUpTime: Date?

    // Live fare display (updated every second)
    @State private var localRideSeconds: Int = 0
    @State private var localWaitSeconds: Int = 0
    @State private var isWaiting = false
    @State private var rideTickerTask: Task<Void, Never>?
    @State private var fareUpdateTask: Task<Void, Never>?
    @State private var customerUser: User?

    // The live ride (updated via Firestore stream)
    private var currentRide: Ride {
        rideService.activeRide ?? ride
    }

    private var isNavigating: Bool {
        currentRide.status == .accepted || currentRide.status == .pickedUp
    }

    // Computed fare based on live local state
    private var liveFare: Double {
        let snap = rideService.navigationSnapshot
        let distKm = snap.distanceKm > 0 ? snap.distanceKm : currentRide.distanceKm
        let rideSec = localRideSeconds > 0 ? localRideSeconds : currentRide.rideSeconds
        let waitSec = currentRide.waitSeconds + localWaitSeconds
        return FareCalculator.realtimeFare(
            distanceKm: distKm,
            rideSeconds: rideSec,
            waitSeconds: waitSec,
            tier: currentRide.tier
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer
            VStack(spacing: 0) {
                topControls
                Spacer()
                if !isPanelExpanded {
                    collapsedPill
                        .padding(.bottom, 24)
                } else {
                    bottomPanel
                }
            }
            if isNavigating {
                fabColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .sheet(isPresented: $showChat) {
            NavigationStack {
                ChatView(rideId: currentRide.id)
                    .environmentObject(authService)
            }
        }
        .onAppear {
            locationService.startBackgroundUpdates()
            Task { customerUser = await authService.getUserById(currentRide.customerId) }
            // Start navigation immediately — startNavigation falls back to the
            // ride's pickup coordinates when GPS is not yet available, so the
            // route and step banner appear at once rather than waiting for the
            // first GPS tick. The real GPS position takes over via onReceive.
            if !navigationStarted {
                navigationStarted = true
                if let loc = locationService.lastLocation {
                    gpsLocation = LatLng(latitude: loc.coordinate.latitude,
                                         longitude: loc.coordinate.longitude)
                    currentBearing = loc.course >= 0 ? loc.course : 0
                } else if let lastKnown = currentRide.driverLocation {
                    // Use Firestore-stored position so the arrow and follow-mode
                    // camera activate instantly before the first GPS reading.
                    gpsLocation = lastKnown
                }
                startNavigation()
            }
        }
        .onDisappear {
            rideService.stopNavigation()
            rideTickerTask?.cancel()
            fareUpdateTask?.cancel()
        }
        .onReceive(locationService.$lastLocation) { location in
            guard let location else { return }
            gpsLocation = LatLng(latitude: location.coordinate.latitude,
                                 longitude: location.coordinate.longitude)
            if !navigationStarted {
                navigationStarted = true
                startNavigation()
            }
            updateNavigation(with: location)
        }
        .onReceive(rideService.navigationSnapshotPublisher) { snap in
            if !snap.routePoints.isEmpty {
                currentRoutePoints = snap.routePoints
            }
            if !snap.trafficSegments.isEmpty {
                currentTrafficSegments = snap.trafficSegments
            }

            let stepIdx = snap.currentStepIndex
            let dist = snap.distanceToNextTurnM

            if let step = snap.currentStep {
                // Update banner text
                if step.instruction != navigationStep {
                    navigationStep = step.instruction
                    navigationManeuver = step.maneuver
                }

                // Reset zone tracking when the step advances
                if stepIdx != lastAnnouncedStepIndex {
                    lastAnnouncedStepIndex = stepIdx
                    lastAnnouncedZone = ""
                }

                // Zone-based announcements (Uber/Bolt pattern)
                // "far"      ~ 300–600 m from turn
                // "near"     ~ 80–300 m from turn
                // "imminent" ~ 0–80 m (at the turn itself)
                let zone: String
                if dist > 300 { zone = "far" }
                else if dist > 80 { zone = "near" }
                else { zone = "imminent" }

                if zone != lastAnnouncedZone {
                    lastAnnouncedZone = zone
                    switch zone {
                    case "far":
                        speakInstruction("Over \(dist) meter, \(step.instruction)")
                    case "near":
                        speakInstruction("Over \(dist) meter, \(step.instruction)")
                    default:
                        speakInstruction(step.instruction)
                    }
                }
            }

            distanceToNextTurnM = dist
            if snap.etaSeconds > 0 {
                etaSeconds = snap.etaSeconds

                // Sync ETA to Firestore so the rider sees the driver's live ETA
                let now = Date()
                if lastEtaWrite == nil || now.timeIntervalSince(lastEtaWrite!) > 15 {
                    lastEtaWrite = now
                    Task { try? await rideService.updateEta(currentRide.id, seconds: snap.etaSeconds) }
                }
            }
            if let snapped = snap.snappedDriverLocation {
                snappedLocation = snapped
            }
        }
        .onReceive(rideService.navigationEventsPublisher) { event in
            switch event {
            case .offRoute:
                isRerouting = true
            case .rerouted:
                isRerouting = false
            }
        }
        .onChange(of: currentRide.status) { _, status in
            isPanelExpanded = true
            isFollowingDriver = true
            switch status {
            case .pickedUp:
                pickedUpTime = Date()
                localRideSeconds = 0
                localWaitSeconds = 0
                startRideTicker()
                startFareUpdateTimer()
            case .cancelled:
                rideTickerTask?.cancel()
                fareUpdateTask?.cancel()
                dismiss()
            default:
                break
            }
        }
        .task(id: isFollowingDriver) {
            guard !isFollowingDriver, isNavigating else { return }
            try? await Task.sleep(for: .seconds(7))
            isFollowingDriver = true
        }
    }

    // MARK: - Ticker & fare update

    private func startRideTicker() {
        rideTickerTask?.cancel()
        rideTickerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                if let t = pickedUpTime {
                    localRideSeconds = Int(Date().timeIntervalSince(t))
                }
                if isWaiting {
                    localWaitSeconds += 1
                }
            }
        }
    }

    private func startFareUpdateTimer() {
        fareUpdateTask?.cancel()
        fareUpdateTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { break }
                let snap = rideService.navigationSnapshot
                let distKm = snap.distanceKm > 0 ? snap.distanceKm : currentRide.distanceKm
                let rideSec = localRideSeconds > 0 ? localRideSeconds : currentRide.rideSeconds
                let waitSec = currentRide.waitSeconds + localWaitSeconds
                try? await rideService.updateFare(
                    currentRide.id,
                    distanceKm: distKm,
                    rideSeconds: rideSec,
                    waitSeconds: waitSec,
                    tier: currentRide.tier
                )
            }
        }
    }

    // MARK: - Navigation Logic

    private func startNavigation(to explicitTarget: LatLng? = nil) {
        let target: LatLng
        if let explicit = explicitTarget {
            target = explicit
        } else {
            switch currentRide.status {
            case .accepted, .arrived:
                target = currentRide.pickupLocation
            default:
                target = currentRide.destinationLocation
            }
        }
        // Priority: live GPS → last known Firestore position → pickup location.
        // Using pickup as origin when neither GPS nor Firestore position is
        // available draws a wrong first route; Firestore position is a far
        // better approximation of where the driver actually is.
        let origin: LatLng
        if let loc = locationService.lastLocation {
            origin = LatLng(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        } else if let driverLoc = currentRide.driverLocation {
            origin = driverLoc
        } else {
            origin = currentRide.pickupLocation
        }
        // Reset announcement state for the new route
        lastAnnouncedStepIndex = -1
        lastAnnouncedZone = ""
        rideService.startNavigation(origin: origin, destination: target) { _ in }
    }

    private func updateNavigation(with location: CLLocation) {
        guard let activeRide = rideService.activeRide else { return }
        if location.course >= 0 {
            currentBearing = location.course
        }
        currentSpeedKmh = max(0, location.speed * 3.6)

        let update = DriverLocationUpdate(
            latLng: LatLng(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            speedKmh: currentSpeedKmh,
            heading: currentBearing
        )
        rideService.onLocation(activeRide.id, update: update)

        Task {
            try? await rideService.updateDriverLocation(activeRide.id, location: update.latLng, bearing: currentBearing)
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        TRAGoogleMapView(
            pickup: currentRide.pickupLocation,
            destination: currentRide.destinationLocation,
            driverLocation: snappedLocation ?? gpsLocation ?? currentRide.driverLocation,
            customerLocation: currentRide.status == .accepted ? currentRide.customerLocation : nil,
            routePoints: currentRoutePoints,
            trafficSegments: currentTrafficSegments,
            bearing: useHeadingUp ? currentBearing : 0,
            speedKmh: currentSpeedKmh,
            followDriver: isFollowingDriver && isNavigating,
            showTraffic: true,
            onUserPanned: { isFollowingDriver = false },
            distanceToNextTurnM: distanceToNextTurnM
        )
        .ignoresSafeArea()
    }

    // MARK: - Top Controls

    private var topControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.gray900)
                        .frame(width: 44, height: 44)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.12), radius: 4)
                }
                .buttonStyle(.plain)

                Spacer()

                StatusChip(label: currentRide.status.chipLabel, color: currentRide.status.chipColor)

                Spacer()

                Button { isMuted.toggle() } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(isMuted ? AppColors.errorRed : AppColors.gray700)
                        .frame(width: 44, height: 44)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.12), radius: 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)

            if isNavigating {
                if isRerouting {
                    reroutingBanner
                        .padding(.horizontal, 16)
                } else if let step = navigationStep {
                    navigationBanner(step: step)
                        .padding(.horizontal, 16)
                } else if currentRoutePoints.isEmpty {
                    loadingBanner
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    private func navigationBanner(step: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColors.boltGreen)
                    .frame(width: 52, height: 52)
                Image(systemName: maneuverIcon(navigationManeuver))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                if distanceToNextTurnM > 0 {
                    Text(formatDistance(distanceToNextTurnM))
                        .font(AppFont.titleMedium())
                        .foregroundStyle(.white)
                }
                Text(step)
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                if let eta = etaSeconds, eta > 0 {
                    Text(formatEta(eta))
                        .font(AppFont.labelSmall())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()
        }
        .padding(14)
        .background(AppColors.darkSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r20))
        .shadow(color: .black.opacity(0.2), radius: 8)
    }

    private var loadingBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.85)
            Text("active.ride.calculating_route")
                .font(AppFont.bodyMedium())
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppColors.darkSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r20))
        .shadow(color: .black.opacity(0.2), radius: 8)
    }

    private var reroutingBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.85)
            Text("active.ride.rerouting")
                .font(AppFont.bodyMedium())
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppColors.warningAmber)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r20))
        .shadow(color: .black.opacity(0.2), radius: 8)
    }

    // MARK: - FABs

    private var fabColumn: some View {
        VStack(spacing: 12) {
            if currentSpeedKmh > 0 {
                VStack(spacing: 1) {
                    Text("\(Int(currentSpeedKmh))")
                        .font(AppFont.titleSmall())
                        .foregroundStyle(.white)
                    Text("active.ride.speed_unit")
                        .font(AppFont.labelSmall())
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.darkSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.15), radius: 4)
            }

            Button {
                useHeadingUp.toggle()
            } label: {
                Image(systemName: useHeadingUp ? "location.north.fill" : "safari")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.boltGreen)
                    .frame(width: 44, height: 44)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.12), radius: 4)
            }
            .buttonStyle(.plain)

            if !isFollowingDriver {
                Button {
                    isFollowingDriver = true
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.boltGreen)
                        .frame(width: 44, height: 44)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.12), radius: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 220)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Bottom Panel

    private var collapsedPill: some View {
        Button {
            withAnimation(.spring(response: 0.3)) { isPanelExpanded = true }
        } label: {
            HStack(spacing: 8) {
                StatusChip(label: currentRide.status.chipLabel, color: currentRide.status.chipColor)
                Image(systemName: "chevron.up")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.gray500)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8)
        }
        .buttonStyle(.plain)
    }

    private var bottomPanel: some View {
        TRABottomSheet {
            VStack(spacing: 16) {
                panelHeader
                Divider()
                panelContent
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private var panelHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentRide.pickupAddress ?? String(localized: "route.pickup_fallback"))
                    .font(AppFont.titleSmall())
                    .foregroundStyle(AppColors.gray900)
                Text("→ \(currentRide.destinationAddress ?? String(localized: "route.destination_fallback"))")
                    .font(AppFont.bodySmall())
                    .foregroundStyle(AppColors.gray500)
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3)) { isPanelExpanded = false }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.gray500)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
    }

    private var panelContent: some View {
        VStack(spacing: 12) {
            // Rider card — shown while en route to pick up
            if currentRide.status == .accepted, let customer = customerUser {
                customerCard(customer)
                Divider()
            }

            // Live fare meter (only shown after pickup)
            if currentRide.status == .pickedUp {
                liveFareMeter
                Divider()
            }

            actionButtons

            TRASecondaryButton(title: "action.chat", icon: "message.fill") {
                showChat = true
            }
        }
    }

    private func customerCard(_ customer: User) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.boltGreenLight)
                    .frame(width: 44, height: 44)
                if let url = customer.photoURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        } else {
                            Text(String(customer.displayName?.prefix(1) ?? "?"))
                                .font(AppFont.titleSmall())
                                .foregroundStyle(AppColors.boltGreen)
                        }
                    }
                } else {
                    Text(String(customer.displayName?.prefix(1) ?? "?"))
                        .font(AppFont.titleSmall())
                        .foregroundStyle(AppColors.boltGreen)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.displayName ?? String(localized: "active.ride.driver_fallback"))
                    .font(AppFont.titleSmall())
                    .foregroundStyle(AppColors.gray900)
                Text("active.ride.your_passenger")
                    .font(AppFont.bodySmall())
                    .foregroundStyle(AppColors.gray500)
            }
            Spacer()
        }
    }

    // MARK: - Live fare meter

    private var liveFareMeter: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(AppColors.boltGreen)
                        .font(.system(size: 18))
                    Text(String(format: "SRD %.2f", liveFare))
                        .font(AppFont.titleSmall())
                        .foregroundStyle(AppColors.boltGreen)
                        .monospacedDigit()
                }
                if isWaiting {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(AppColors.warningAmber)
                            .frame(width: 6, height: 6)
                        Text(String(format: String(localized: "active.ride.waiting"), formatWaitTime(localWaitSeconds)))
                            .font(AppFont.labelSmall())
                            .foregroundStyle(AppColors.warningAmber)
                    }
                } else {
                    Text(currentRide.tier.displayName + " · " + String(localized: "active.ride.wait_rate"))
                        .font(AppFont.labelSmall())
                        .foregroundStyle(AppColors.gray500)
                }
            }

            Spacer()

            Button {
                if isWaiting {
                    isWaiting = false
                } else {
                    isWaiting = true
                }
            } label: {
                Label(
                    isWaiting ? String(localized: "active.ride.stop_wait") : String(localized: "active.ride.start_wait"),
                    systemImage: isWaiting ? "pause.circle.fill" : "clock.fill"
                )
                .font(AppFont.labelSmall())
                .foregroundStyle(isWaiting ? .white : AppColors.warningAmber)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isWaiting ? AppColors.warningAmber : AppColors.warningAmber.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(AppColors.boltGreenLight)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r12))
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        Group {
            switch currentRide.status {
            case .accepted:
                TRAPrimaryButton(
                    title: "active.ride.arrived_customer",
                    isDisabled: !networkMonitor.isOnline
                ) {
                    update(.arrived)
                }

            case .arrived:
                TRAPrimaryButton(
                    title: "active.ride.passenger_picked_up",
                    isDisabled: !networkMonitor.isOnline
                ) {
                    update(.pickedUp)
                    startNavigation(to: currentRide.destinationLocation)
                }

            case .pickedUp:
                TRAPrimaryButton(
                    title: "active.ride.complete_ride",
                    isDisabled: !networkMonitor.isOnline
                ) {
                    finalizeCurrentRide()
                }

            default:
                EmptyView()
            }
        }
    }

    // MARK: - Status Updates

    private func update(_ status: RideStatus) {
        Task { try? await rideService.updateStatus(currentRide.id, status: status) }
    }

    private func finalizeCurrentRide() {
        rideTickerTask?.cancel()
        fareUpdateTask?.cancel()
        Task {
            let snap = rideService.navigationSnapshot
            let distanceKm = snap.distanceKm > 0 ? snap.distanceKm : currentRide.distanceKm
            let rideSeconds = localRideSeconds > 0 ? localRideSeconds : (pickedUpTime.map { Int(Date().timeIntervalSince($0)) } ?? currentRide.rideSeconds)
            let totalWaitSeconds = currentRide.waitSeconds + localWaitSeconds

            let finalFare = FareCalculator.realtimeFare(
                distanceKm: distanceKm,
                rideSeconds: rideSeconds,
                waitSeconds: totalWaitSeconds,
                tier: currentRide.tier
            )

            try? await rideService.finalizeRide(
                currentRide.id,
                distanceKm: distanceKm,
                rideSeconds: rideSeconds,
                waitSeconds: totalWaitSeconds,
                totalFareFinal: finalFare
            )
            await MainActor.run { dismiss() }
        }
    }

    // MARK: - Helpers

    private func formatWaitTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    private func speakInstruction(_ text: String) {
        guard !isMuted, text != lastSpokenStep else { return }
        lastSpokenStep = text
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        let langCode = UserDefaults.standard.string(forKey: "app_language") ?? "nl"
        utterance.voice = AVSpeechSynthesisVoice(language: langCode)
        utterance.rate = 0.52
        speechSynthesizer.speak(utterance)
    }

    private func maneuverIcon(_ maneuver: String?) -> String {
        switch maneuver {
        case "TURN_LEFT", "TURN_SLIGHT_LEFT", "TURN_SHARP_LEFT",
             "FORK_LEFT", "RAMP_LEFT":
            return "arrow.turn.up.left"
        case "TURN_RIGHT", "TURN_SLIGHT_RIGHT", "TURN_SHARP_RIGHT",
             "FORK_RIGHT", "RAMP_RIGHT":
            return "arrow.turn.up.right"
        case "UTURN_LEFT", "UTURN_RIGHT":
            return "arrow.uturn.up"
        case "ROUNDABOUT_LEFT", "ROUNDABOUT_RIGHT":
            return "arrow.uturn.right"
        case "STRAIGHT", "NAME_CHANGE", "DEPART":
            return "arrow.up"
        case "MERGE":
            return "arrow.merge"
        case "FERRY", "FERRY_TRAIN":
            return "ferry"
        default:
            return "arrow.up"
        }
    }

    private func formatDistance(_ meters: Int) -> String {
        meters >= 1000 ? String(format: "%.1f km", Double(meters) / 1000) : "\(meters) m"
    }

    private func formatEta(_ seconds: Int) -> String {
        let cal = Calendar.current
        let arrival = cal.date(byAdding: .second, value: seconds, to: Date()) ?? Date()
        let hm = arrival.formatted(.dateTime.hour().minute())
        let minutes = max(1, (seconds + 30) / 60)
        return String(format: String(localized: "active.ride.eta"), hm, minutes)
    }
}

#Preview {
    let ride = Ride(
        id: "demo", customerId: "c1",
        pickupLocation: LatLng(latitude: 52.37, longitude: 4.89),
        destinationLocation: LatLng(latitude: 52.31, longitude: 4.76),
        pickupAddress: "Dam Square",
        destinationAddress: "Schiphol"
    )
    DriverActiveRideView(ride: ride)
        .environmentObject(
            RideService(
                repository: InMemoryRideRepository(),
                navigationManager: NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil))
            )
        )
        .environmentObject(LocationService())
        .environmentObject(NetworkMonitor.preview)
}
