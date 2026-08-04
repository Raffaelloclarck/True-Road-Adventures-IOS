import SwiftUI
import CoreLocation

struct RiderActiveRideView: View {
    let ride: Ride
    /// When true (e.g. opened from chat push), the chat sheet is shown once after first appear.
    var presentChatOnAppear: Bool = false

    @EnvironmentObject private var rideService: RideService
    @EnvironmentObject private var locationService: LocationService

    /// Canonical Firestore document for this screen's `ride.id` (preferred over global `activeRide`).
    @State private var documentRide: Ride?

    /// Resolved model: document stream for this id, else matching `activeRide`, else the initial `ride`.
    private var currentRide: Ride {
        if let doc = documentRide, doc.id == ride.id {
            return doc
        }
        if let active = rideService.activeRide, active.id == ride.id {
            return active
        }
        return ride
    }
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var driverUser: User?
    @State private var driverRating: Double?
    @State private var routePoints: [Coordinate2D] = []
    @State private var trafficSegments: [TrafficSegment] = []
    @State private var directionsEtaSeconds: Int?
    @State private var routeError = false
    @State private var locationUpdateCount = 0

    // Speed estimation from consecutive driver location deltas
    @State private var estimatedSpeedKmh: Double = 0
    @State private var lastDriverLoc: LatLng?
    @State private var lastDriverLocTime: Date?
    @State private var lastCustomerLocationUpload: Date?
    @State private var lastCustomerLocationUploaded: LatLng?

    // Camera follow state (mirrors the driver-side pattern)
    @State private var isFollowingDriver = true

    @State private var showCompletion = false
    @State private var showChat = false
    @State private var didPresentChatFromPush = false
    @State private var showShareSheet = false
    @State private var showCancelConfirm = false
    @State private var cancelError: Error? = nil
    @State private var shareItems: [Any] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer
            VStack(spacing: 0) {
                topBar
                if currentRide.status == .accepted, currentRide.driverLocation == nil {
                    preparingBanner
                }
                Spacer()
                ridePanel
            }
        // Re-center button — shown after rider pans away while driver is en route or during ride
        if (currentRide.status == .accepted || currentRide.status == .pickedUp) && !isFollowingDriver {
                Button { isFollowingDriver = true } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.boltGreen)
                        .frame(width: 44, height: 44)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.12), radius: 4)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 120)
                .padding(.trailing, 16)
            }
        }
        .ignoresSafeArea(.all, edges: .top)
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showCompletion) {
            RiderRideCompletionView(
                ride: currentRide,
                driverUser: driverUser,
                onDismiss: { dismiss() }
            )
            .environmentObject(rideService)
            .environmentObject(authService)
            .environmentObject(networkMonitor)
        }
        .sheet(isPresented: $showChat) {
            NavigationStack {
                ChatView(rideId: ride.id)
                    .environmentObject(authService)
                    .environmentObject(rideService)
            }
        }
        .onAppear {
            locationService.startHighAccuracyUpdates()
            if presentChatOnAppear, !didPresentChatFromPush {
                didPresentChatFromPush = true
                showChat = true
            }
        }
        .onDisappear {
            locationService.startUpdating()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
                .ignoresSafeArea()
        }
        .confirmationDialog(
            String(localized: "ride.cancel.title"),
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "ride.cancel.confirm"), role: .destructive) {
                Task {
                    do {
                        try await rideService.updateStatus(ride.id, status: .cancelled)
                        await MainActor.run { dismiss() }
                    } catch {
                        await MainActor.run { cancelError = error }
                    }
                }
            }
            Button(String(localized: "ride.cancel.back"), role: .cancel) {}
        } message: {
            Text("ride.cancel.message")
        }
        .task(id: currentRide.driverId) {
            await loadDriverData(for: currentRide.driverId)
        }
        .task(id: routeTaskKey) {
            await loadRoute()
        }
        // Auto re-enable follow after 12 s when the rider panned away
        .task(id: isFollowingDriver) {
            guard !isFollowingDriver,
                  currentRide.status == .accepted || currentRide.status == .pickedUp else { return }
            try? await Task.sleep(for: .seconds(12))
            isFollowingDriver = true
        }
        .onChange(of: currentRide.driverLocation) { _, newLocation in
            guard newLocation != nil else { return }
            // Speed estimation from consecutive driver location deltas
            if let prev = lastDriverLoc, let prevTime = lastDriverLocTime, let cur = newLocation {
                let distM = haversineM(prev, cur)
                let elapsed = Date().timeIntervalSince(prevTime)
                if elapsed > 0 {
                    estimatedSpeedKmh = min((distM / elapsed) * 3.6, 130)
                }
            }
            lastDriverLoc = newLocation
            lastDriverLocTime = Date()
            locationUpdateCount += 1
            // refresh route when location first appears or every 10 updates
            if locationUpdateCount == 1 || locationUpdateCount % 10 == 0 {
                Task { await loadRoute() }
            }
        }
        .onChange(of: currentRide.status) { _, newStatus in
            if newStatus == .pickedUp || newStatus == .accepted { isFollowingDriver = true }
            if newStatus == .completed {
                showCompletion = true
            }
            if newStatus == .accepted {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
        .onReceive(locationService.$lastLocation) { location in
            guard let location else { return }
            publishCustomerLocationIfNeeded(location)
        }
        // Firestore document listener: keeps status / driver / location in sync for this ride id
        // even when global `activeRide` points at a different row or is temporarily nil.
        .task(id: ride.id) {
            for await updatedRide in rideService.subscribeToRide(ride.id) {
                guard let updated = updatedRide else { break }
                await MainActor.run {
                    documentRide = updated
                    if updated.status == .completed, !showCompletion {
                        showCompletion = true
                    }
                    if updated.status == .cancelled {
                        dismiss()
                    }
                }
                if updated.status == .cancelled { break }
            }
        }
        .alert(
            String(localized: "ride.cancel.error.title"),
            isPresented: Binding(get: { cancelError != nil }, set: { if !$0 { cancelError = nil } })
        ) {
            Button(String(localized: "action.ok"), role: .cancel) { cancelError = nil }
        } message: {
            Text(cancelError?.localizedDescription ?? "")
        }
    }

    // Key that changes when we need a fresh route (status changed).
    // Driver lat/lng is intentionally excluded: live location updates are handled
    // by onChange(of: currentRide.driverLocation) every 10 ticks. Including raw
    // coordinates here caused a new Directions API fetch on every Firestore update.
    private var routeTaskKey: String {
        currentRide.status.rawValue
    }

    // MARK: - Map

    private var mapLayer: some View {
        TRAGoogleMapView(
            pickup: currentRide.pickupLocation,
            destination: currentRide.destinationLocation,
            driverLocation: currentRide.driverLocation,
            customerLocation: nil,
            routePoints: routePoints,
            trafficSegments: trafficSegments,
            bearing: currentRide.driverBearing ?? 0,
            speedKmh: estimatedSpeedKmh,
            followDriver: (currentRide.status == .accepted || currentRide.status == .pickedUp) && isFollowingDriver,
            showTraffic: false,
            onUserPanned: { isFollowingDriver = false }
        )
        .ignoresSafeArea()
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
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
            .padding(.leading, 16)
            .padding(.top, 56)

            Spacer()

            StatusChip(label: currentRide.status.chipLabel, color: currentRide.status.chipColor)
                .padding(.top, 56)
                .padding(.trailing, 16)
        }
    }

    // MARK: - Preparing navigation banner

    private var preparingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
                .tint(AppColors.boltGreen)
            Text("active.ride.driver_preparing")
                .font(AppFont.labelSmall())
                .foregroundStyle(AppColors.gray700)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.92))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.08), radius: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: currentRide.driverLocation == nil)
    }

    // MARK: - Bottom panel

    private var ridePanel: some View {
        TRABottomSheet {
            VStack(spacing: 16) {
                RideStatusIndicator(currentStatus: currentRide.status)
                    .padding(.horizontal, 16)

                Divider()

                // Show final fare prominently when ride is completed
                if currentRide.status == .completed {
                    finalFareBanner(fare: currentRide.totalFareFinal ?? currentRide.totalFareRealtime)
                        .padding(.horizontal, 16)
                    Divider()
                }

                driverCard
                    .padding(.horizontal, 16)

                Divider()

                actionButtons
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Final fare banner

    private func finalFareBanner(fare: Double) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(AppColors.boltGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text("active.ride.total_to_pay")
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.gray500)
                Text(String(format: "SRD %.2f", fare))
                    .font(AppFont.titleMedium())
                    .foregroundStyle(AppColors.boltGreen)
            }
            Spacer()
            Text(currentRide.tier.displayName)
                .font(AppFont.labelSmall())
                .foregroundStyle(AppColors.gray700)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AppColors.backgroundCard)
                .clipShape(Capsule())
        }
        .padding(14)
        .background(AppColors.boltGreenLight)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r12))
    }

    // MARK: - Driver card

    private var driverCard: some View {
        HStack(spacing: 14) {
            driverAvatar

            VStack(alignment: .leading, spacing: 4) {
                Text(driverUser?.displayName ?? String(localized: "active.ride.driver_fallback"))
                    .font(AppFont.titleSmall())
                    .foregroundStyle(AppColors.gray900)
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.starYellow)
                    Text(driverRatingLabel)
                        .font(AppFont.labelSmall())
                        .foregroundStyle(AppColors.gray700)
                    if let vehicleLabel = vehicleLabel {
                        Text("·")
                            .foregroundStyle(AppColors.gray500)
                        Text(vehicleLabel)
                            .font(AppFont.labelSmall())
                            .foregroundStyle(AppColors.gray500)
                    }
                }
            }

            Spacer()

            etaView
        }
    }

    @ViewBuilder
    private var driverAvatar: some View {
        if let photoURL = driverUser?.photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                case .failure, .empty:
                    driverInitialCircle
                @unknown default:
                    driverInitialCircle
                }
            }
        } else {
            driverInitialCircle
        }
    }

    private var driverInitialCircle: some View {
        ZStack {
            Circle()
                .fill(AppColors.boltGreenLight)
                .frame(width: 52, height: 52)
            if let name = driverUser?.displayName, let first = name.first {
                Text(String(first).uppercased())
                    .font(AppFont.titleSmall())
                    .foregroundStyle(AppColors.boltGreen)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.boltGreen)
            }
        }
    }

    @ViewBuilder
    private var etaView: some View {
        let seconds = directionsEtaSeconds ?? currentRide.etaToPickupSeconds
        if let eta = seconds {
            VStack(spacing: 2) {
                Text("\(max(1, eta / 60))")
                    .font(AppFont.titleMedium())
                    .foregroundStyle(AppColors.boltGreen)
                Text("min")
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.gray500)
            }
        }
    }

    private var driverRatingLabel: String {
        if let r = driverRating { return String(format: "%.1f", r) }
        if let r = driverUser?.rating { return String(format: "%.1f", r) }
        return "–"
    }

    private var vehicleLabel: String? {
        let v = driverUser?.vehicle
        if let type = v?.vehicleType, let plate = v?.licensePlate {
            return "\(type) · \(plate)"
        }
        if let type = v?.vehicleType { return type }
        if let plate = v?.licensePlate { return plate }
        return nil
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            actionButton(icon: "message.fill",       label: "action.chat",         color: AppColors.whatsAppGreen,  isDisabled: false) { showChat = true }
            actionButton(icon: "phone.fill",         label: "action.call",         color: AppColors.accentBlue,     isDisabled: false) { callDriver() }
            actionButton(icon: "square.and.arrow.up",label: "action.share",        color: AppColors.gray500,        isDisabled: false) { shareLocation() }
            if currentRide.status == .searching {
                actionButton(icon: "xmark",              label: "action.cancel_short", color: AppColors.errorRed,       isDisabled: !networkMonitor.isOnline) {
                    showCancelConfirm = true
                }
            }
        }
    }

    private func actionButton(icon: String, label: LocalizedStringKey, color: Color, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.gray700)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    // MARK: - Async loaders

    private func loadDriverData(for driverId: String?) async {
        guard let driverId else {
            driverUser = nil
            driverRating = nil
            return
        }
        async let userTask = authService.getUserById(driverId)
        async let ratingsTask = authService.fetchRatings(for: driverId)
        let (user, ratings) = await (userTask, ratingsTask)
        driverUser = user
        if !ratings.isEmpty {
            let avg = Double(ratings.map(\.score).reduce(0, +)) / Double(ratings.count)
            driverRating = avg
        } else {
            driverRating = nil
        }
    }

    private func loadRoute() async {
        routeError = false

        let result: DirectionsResult
        switch currentRide.status {

        case .searching:
            result = await rideService.fetchRoute(
                from: currentRide.pickupLocation,
                to: currentRide.destinationLocation
            )

        case .accepted, .arrived:
            guard let driverLoc = currentRide.driverLocation else { return }
            result = await rideService.fetchRoute(from: driverLoc, to: currentRide.pickupLocation)

        case .pickedUp:
            let origin = currentRide.driverLocation ?? currentRide.pickupLocation
            result = await rideService.fetchRoute(from: origin, to: currentRide.destinationLocation)

        default:
            return
        }

        if result.points.isEmpty {
            routeError = true
        } else {
            routePoints = result.points
            trafficSegments = result.trafficSegments
            directionsEtaSeconds = result.totalDurationSeconds
        }
    }

    private func publishCustomerLocationIfNeeded(_ location: CLLocation) {
        guard currentRide.status == .accepted || currentRide.status == .arrived else { return }
        let latLng = LatLng(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        if let last = lastCustomerLocationUploaded, let lastTime = lastCustomerLocationUpload {
            let movedM = haversineM(last, latLng)
            let elapsed = Date().timeIntervalSince(lastTime)
            if movedM < 15, elapsed < 5 { return }
        }

        lastCustomerLocationUploaded = latLng
        lastCustomerLocationUpload = Date()
        Task {
            try? await rideService.updateCustomerLocation(currentRide.id, location: latLng)
        }
    }

    // MARK: - Actions

    private func callDriver() {
        let phone = driverUser?.phoneNumber ?? ""
        guard !phone.isEmpty, let url = URL(string: "tel://\(phone)") else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private func shareLocation() {
        let pickupAddress = currentRide.pickupAddress ?? String(localized: "route.pickup_fallback")
        let destAddress = currentRide.destinationAddress ?? String(localized: "route.destination_fallback")
        let text = String(format: String(localized: "active.ride.share_text"), pickupAddress, destAddress)
        shareItems = [text]
        showShareSheet = true
    }

    // MARK: - Geometry

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
}

// MARK: - UIActivityViewController wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let ride = Ride(
        id: "demo",
        customerId: "c1",
        pickupLocation: LatLng(latitude: 52.37, longitude: 4.89),
        destinationLocation: LatLng(latitude: 52.31, longitude: 4.76),
        pickupAddress: "Dam Square",
        destinationAddress: "Schiphol"
    )
    RiderActiveRideView(ride: ride)
        .environmentObject(
            RideService(
                repository: InMemoryRideRepository(),
                navigationManager: NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil))
            )
        )
        .environmentObject(NetworkMonitor.preview)
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
        .environmentObject(LocationService())
}
