import SwiftUI
import CoreLocation
import Combine
#if canImport(GoogleMaps)
import GoogleMaps
#endif

// MARK: - ViewModel

final class RiderHomeViewModel: ObservableObject {
    @Published var pickupText: String = ""
    @Published var destinationText: String = ""
    @Published var scheduledAt: Date = .now
    @Published var isScheduling: Bool = false
    @Published var status: String = ""

    private let container: AppContainer
    let currentUser: User

    init(container: AppContainer, currentUser: User) {
        self.container = container
        self.currentUser = currentUser
    }
}

// MARK: - Ride request presentation item

private struct RideRequestPresentation: Identifiable {
    let id = UUID()
    let prefillDestination: String?
}

// MARK: - Main View

struct RiderHomeView: View {
    @ObservedObject var viewModel: RiderHomeViewModel
    @EnvironmentObject private var rideService: RideService
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var pushNavigationStore: PushNavigationStore
    @EnvironmentObject private var discountCodeService: DiscountCodeService
    @EnvironmentObject private var paymentService: PaymentService
    @Environment(\.openDrawer) private var openDrawer

    @State private var rideRequestPresentation: RideRequestPresentation? = nil
    @State private var showRideRequestScheduled = false
    @State private var showActiveRideFull = false
    @State private var pendingPresentChatAfterRidePush = false
    @State private var capturedActiveRide: Ride? = nil
    @State private var showChat = false
    @State private var showSavedPlaces = false
    @State private var showPromotions = false
    @State private var showCompletionFromHome = false
    @State private var completedRideForHome: Ride? = nil
    @State private var isCancellingRide = false
    @State private var cancelError: Error? = nil
    // Optimistically hide the active-ride card the moment the user confirms
    // cancel, without waiting for the Firestore listener round-trip.
    @State private var cancelledRideId: String? = nil

    // Route polyline shown on the home map while an active ride is in progress.
    @State private var homeRoutePoints: [Coordinate2D] = []
    @State private var homeTrafficSegments: [TrafficSegment] = []

    /// Changes when the ride status advances or the driver location first appears,
    /// triggering a fresh route fetch without re-fetching on every GPS tick.
    private var homeRouteKey: String {
        guard let ride = rideService.activeRide else { return "" }
        let hasDriver = ride.driverLocation != nil ? "1" : "0"
        return "\(ride.id)-\(ride.status.rawValue)-\(hasDriver)"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer

            VStack(spacing: 0) {
                floatingMenuButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 56)

                Spacer()

                if let ride = rideService.activeRide,
                   ride.status != .cancelled,
                   ride.status != .completed,
                   ride.id != cancelledRideId {
                    activeRideSheet(ride: ride)
                } else {
                    searchSheet
                }
            }
        }
        .ignoresSafeArea(.all, edges: .top)
        .navigationBarHidden(true)
        .onAppear {
            locationService.startUpdating()
        }
        .fullScreenCover(item: $rideRequestPresentation) { presentation in
            RiderRideRequestView(scheduledAt: nil, prefillDestination: presentation.prefillDestination)
                .environmentObject(rideService)
                .environmentObject(networkMonitor)
                .environmentObject(locationService)
                .environmentObject(authService)
                .environmentObject(discountCodeService)
                .environmentObject(paymentService)
        }
        .fullScreenCover(isPresented: $showRideRequestScheduled) {
            RiderRideRequestView(scheduledAt: viewModel.scheduledAt)
                .environmentObject(rideService)
                .environmentObject(networkMonitor)
                .environmentObject(locationService)
                .environmentObject(authService)
                .environmentObject(discountCodeService)
                .environmentObject(paymentService)
        }
        .fullScreenCover(isPresented: $showActiveRideFull, onDismiss: {
            capturedActiveRide = nil
            pendingPresentChatAfterRidePush = false
        }) {
            if let ride = capturedActiveRide {
                RiderActiveRideView(
                    ride: ride,
                    presentChatOnAppear: pendingPresentChatAfterRidePush
                )
                    .environmentObject(rideService)
                    .environmentObject(networkMonitor)
                    .environmentObject(authService)
                    .environmentObject(paymentService)
            }
        }
        .fullScreenCover(isPresented: $showCompletionFromHome, onDismiss: { completedRideForHome = nil }) {
            if let ride = completedRideForHome {
                RiderRideCompletionView(
                    ride: ride,
                    driverUser: nil,
                    onDismiss: { showCompletionFromHome = false }
                )
                .environmentObject(rideService)
                .environmentObject(authService)
                .environmentObject(networkMonitor)
                .environmentObject(paymentService)
            }
        }
        .sheet(isPresented: $showSavedPlaces) {
            NavigationStack {
                RiderSavedPlacesView()
                    .environmentObject(authService)
            }
        }
        .sheet(isPresented: $showPromotions) {
            NavigationStack {
                RiderPromotionsView(currentUser: viewModel.currentUser)
                    .environmentObject(discountCodeService)
            }
        }
        .sheet(isPresented: $showChat) {
            if let ride = rideService.activeRide {
                NavigationStack {
                    ChatView(rideId: ride.id)
                        .environmentObject(authService)
                        .environmentObject(rideService)
                }
            }
        }
        // Subscribe directly to the active ride so we can detect completion and
        // cancellation even when the full active-ride view is not open yet.
        // Auto-navigation for accepted/arrived/pickedUp is handled via onChange above.
        .task(id: rideService.activeRide?.id) {
            guard let activeRide = rideService.activeRide else { return }
            for await updatedRide in rideService.subscribeToRide(activeRide.id) {
                guard let updated = updatedRide else { break }
                if updated.status == .completed, !showActiveRideFull, !showCompletionFromHome {
                    completedRideForHome = updated
                    showCompletionFromHome = true
                    break
                }
                if updated.status == .cancelled { break }
            }
        }
        // Keep capturedActiveRide in sync while the active-ride cover is open.
        // When activeRide becomes nil (ride completed/cancelled), we intentionally
        // do NOT clear capturedActiveRide so the cover body never renders blank.
        .onChange(of: rideService.activeRide) { _, newRide in
            if newRide == nil {
                homeRoutePoints = []
                homeTrafficSegments = []
                cancelledRideId = nil
            }
            if !showActiveRideFull,
               let newRide,
               newRide.status == .accepted || newRide.status == .arrived || newRide.status == .pickedUp {
                capturedActiveRide = newRide
                showActiveRideFull = true
                return
            }
            guard showActiveRideFull, let newRide else { return }
            capturedActiveRide = newRide
        }
        .onAppear {
            handlePushIntent(pushNavigationStore.pending)
        }
        .onChange(of: pushNavigationStore.pending) { _, intent in
            handlePushIntent(intent)
        }
        // Fetch the route whenever the ride status advances or the driver location
        // first appears. The key does not change on every GPS update, so this
        // fires only a handful of times per trip.
        .task(id: homeRouteKey) {
            guard let ride = rideService.activeRide,
                  ride.status == .searching || ride.status == .accepted || ride.status == .arrived || ride.status == .pickedUp
            else { return }
            let origin: LatLng
            let destination: LatLng
            if ride.status == .searching {
                // No driver yet — show the full trip route (pickup → destination).
                origin = ride.pickupLocation
                destination = ride.destinationLocation
            } else if ride.status == .pickedUp {
                // Rider is in the car — show remaining route to destination.
                origin = ride.driverLocation ?? ride.pickupLocation
                destination = ride.destinationLocation
            } else {
                // Driver accepted/arrived — show route from driver to pickup.
                origin = ride.driverLocation ?? ride.pickupLocation
                destination = ride.pickupLocation
            }
            let result = await rideService.fetchRoute(from: origin, to: destination)
            if !result.points.isEmpty {
                homeRoutePoints = result.points
                homeTrafficSegments = result.trafficSegments
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

    // MARK: Map
    private var mapLayer: some View {
        Group {
            #if canImport(GoogleMaps)
            let activeRide = rideService.activeRide
            let isPickedUp = activeRide?.status == .pickedUp
            TRAGoogleMapView(
                // Pre-pickup: show both endpoints so the rider sees the driver
                // approaching. Post-pickup: hide the pickup pin (already done)
                // and let the camera fit driver + destination instead.
                pickup: isPickedUp ? nil : activeRide?.pickupLocation,
                destination: activeRide?.destinationLocation,
                driverLocation: activeRide?.driverLocation,
                customerLocation: nil,
                userLocation: locationService.lastLocation.map {
                    LatLng(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                },
                routePoints: homeRoutePoints,
                trafficSegments: homeTrafficSegments,
                bearing: 0,
                speedKmh: 0,
                followDriver: false,
                showTraffic: false,
                onUserPanned: {},
                cameraResetKey: activeRide?.status.rawValue ?? ""
            )
            .ignoresSafeArea()
            #else
            AppColors.boltGreenLight
                .ignoresSafeArea()
                .overlay(
                    Image(systemName: "map.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(AppColors.boltGreen.opacity(0.3))
                )
            #endif
        }
    }

    // MARK: Floating menu button
    private var floatingMenuButton: some View {
        Button {
            openDrawer()
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.boltGreen)
                .frame(width: 44, height: 44)
                .background(Color.white)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: Search Sheet
    private var searchSheet: some View {
        TRABottomSheet {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider()

                scheduleRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { showRideRequestScheduled = true }

                Divider()

                recentPlacesSection

                serviceTiles
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
    }

    private var searchBar: some View {
        Button {
            rideRequestPresentation = RideRequestPresentation(prefillDestination: nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.gray500)
                Text("home.where_to")
                    .font(AppFont.bodyLarge())
                    .foregroundStyle(AppColors.gray500)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(AppColors.gray100)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r12))
        }
        .buttonStyle(.plain)
    }

    private var scheduleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.boltGreen)
            Text("home.schedule_ride")
                .font(AppFont.bodyMedium())
                .foregroundStyle(AppColors.gray700)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.gray500)
        }
    }

    private var recentPlacesSection: some View {
        VStack(spacing: 0) {
            let homeAddress = authService.state.user?.savedPlaces.home
            let workAddress = authService.state.user?.savedPlaces.work

            recentPlaceRow(
                icon: "house.fill",
                title: String(localized: "home.home_label"),
                subtitle: homeAddress ?? String(localized: "home.home_add"),
                action: homeAddress != nil ? { showRideRequestWithDestination(homeAddress!) } : nil
            )
            Divider().padding(.leading, 56)
            recentPlaceRow(
                icon: "briefcase.fill",
                title: String(localized: "home.work_label"),
                subtitle: workAddress ?? String(localized: "home.work_add"),
                action: workAddress != nil ? { showRideRequestWithDestination(workAddress!) } : nil
            )
            Divider()
        }
    }

    private func recentPlaceRow(icon: String, title: String, subtitle: String, action: (() -> Void)?) -> some View {
        Button {
            if let action { action() } else { showSavedPlaces = true }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.boltGreen.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.boltGreen)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppFont.titleSmall()).foregroundStyle(AppColors.gray900)
                    Text(subtitle).font(AppFont.bodySmall()).foregroundStyle(AppColors.gray500)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func showRideRequestWithDestination(_ destination: String) {
        rideRequestPresentation = RideRequestPresentation(prefillDestination: destination)
    }

    private func handlePushIntent(_ intent: PushNotificationIntent?) {
        guard let intent else { return }
        switch intent.screen {
        case .home:
            pushNavigationStore.clearPending()
            return
        case .activeRide:
            guard let rideId = intent.rideId else { pushNavigationStore.clearPending(); return }
            pendingPresentChatAfterRidePush = false
            openActiveRideFromPushIfNeeded(rideId: rideId)
        case .chat:
            guard let rideId = intent.rideId else { pushNavigationStore.clearPending(); return }
            pendingPresentChatAfterRidePush = true
            openActiveRideFromPushIfNeeded(rideId: rideId)
        case .promotions:
            showPromotions = true
            pushNavigationStore.clearPending()
        }
    }

    private func openActiveRideFromPushIfNeeded(rideId: String) {
        if let activeRide = rideService.activeRide, activeRide.id == rideId {
            capturedActiveRide = activeRide
            showActiveRideFull = true
            pushNavigationStore.clearPending()
            return
        }
        // Race: activeRide not yet in RideService — subscribe until the ride arrives.
        pushNavigationStore.clearPending()
        Task {
            for await ride in rideService.subscribeToRide(rideId) {
                guard let ride else { break }
                await MainActor.run {
                    capturedActiveRide = ride
                    showActiveRideFull = true
                }
                break
            }
        }
    }

    private var serviceTiles: some View {
        HStack {
            serviceTile(icon: "car.fill", label: String(localized: "home.service.standard"), price: "SRD \(Int(FareCalculator.startFare))")
            Spacer()
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    private func serviceTile(icon: String, label: String, price: String) -> some View {
        Button {
            rideRequestPresentation = RideRequestPresentation(prefillDestination: nil)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.boltGreen)
                Text(label)
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.gray700)
                Text(price)
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.gray500)
            }
            .frame(width: 76, height: 80)
            .background(AppColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r20))
        }
        .buttonStyle(.plain)
    }

    // MARK: Active Ride Sheet
    private func activeRideSheet(ride: Ride) -> some View {
        TRABottomSheet {
            VStack(spacing: 16) {
                Button {
                    capturedActiveRide = ride
                    showActiveRideFull = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("home.active_ride")
                                .font(AppFont.titleSmall())
                                .foregroundStyle(AppColors.gray500)
                            Text(ride.destinationAddress ?? String(localized: "route.destination_fallback"))
                                .font(AppFont.titleMedium())
                                .foregroundStyle(AppColors.gray900)
                        }
                        Spacer()
                        StatusChip(label: ride.status.chipLabel, color: ride.status.chipColor)
                    }
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)

                RideStatusIndicator(currentStatus: ride.status)
                    .padding(.horizontal, 16)

                if let eta = ride.etaToPickupSeconds {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(AppColors.boltGreen)
                        Text(String(format: String(localized: "home.eta"), eta / 60))
                            .font(AppFont.bodyMedium())
                            .foregroundStyle(AppColors.gray700)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }

                HStack(spacing: 12) {
                    if ride.status == .searching {
                        TRASecondaryButton(
                            title: "action.cancel_short",
                            isDisabled: isCancellingRide || !networkMonitor.isOnline,
                            icon: "xmark"
                        ) {
                            guard !isCancellingRide else { return }
                            isCancellingRide = true
                            let rideId = ride.id
                            Task {
                                do {
                                    try await rideService.updateStatus(rideId, status: .cancelled)
                                    await MainActor.run {
                                        cancelledRideId = rideId
                                        isCancellingRide = false
                                    }
                                } catch {
                                    await MainActor.run {
                                        isCancellingRide = false
                                        cancelError = error
                                    }
                                }
                            }
                        }
                    }

                    TRAPrimaryButton(title: "action.chat") {
                        showChat = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .padding(.top, 8)
        }
    }
}


#Preview {
    RiderHomeView(
        viewModel: RiderHomeViewModel(
            container: AppContainer(),
            currentUser: User(id: "demo", email: "demo", displayName: "Demo", role: .customer)
        )
    )
    .environmentObject(AuthService(repository: InMemoryAuthRepository()))
    .environmentObject(
        RideService(
            repository: InMemoryRideRepository(),
            navigationManager: NavigationSessionManager(
                directionsClient: DirectionsClient(apiKey: nil)
            )
        )
    )
    .environmentObject(LocationService())
    .environmentObject(NetworkMonitor.preview)
    .environmentObject(PushNavigationStore())
}
