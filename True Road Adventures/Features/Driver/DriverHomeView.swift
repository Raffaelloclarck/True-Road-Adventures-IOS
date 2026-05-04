import SwiftUI
import CoreLocation
import Combine

// MARK: - ViewModel

final class DriverHomeViewModel: ObservableObject {
    @Published var statusMessage: String = String(localized: "driver.status.ready")
    @Published var isOnline: Bool = false
    @Published var isLoading: Bool = false

    private(set) var seenRideIds: Set<String> = []

    private let container: AppContainer
    let currentUser: User

    init(container: AppContainer, currentUser: User) {
        self.container = container
        self.currentUser = currentUser
        self.isOnline = currentUser.isDriverOnline
        self.statusMessage = currentUser.isDriverOnline
            ? String(localized: "driver.status.online")
            : String(localized: "driver.status.ready")
    }

    func toggleOnline(isOn: Bool, authService: AuthService) {
        isLoading = true
        Task {
            await authService.setDriverOnline(isOn)
            await MainActor.run {
                isOnline = isOn
                statusMessage = isOn
                    ? String(localized: "driver.status.online")
                    : String(localized: "driver.status.offline")
                isLoading = false
            }
        }
    }

    func accept(ride: Ride, rideService: RideService) {
        Task {
            do {
                try await rideService.acceptRide(ride.id, driverId: currentUser.id)
                await MainActor.run { statusMessage = String(localized: "driver.status.accepted") }
            } catch RideService.RideActionError.offline {
                await MainActor.run { statusMessage = String(localized: "driver.status.accept_failed_offline") }
            } catch {
                await MainActor.run { statusMessage = String(format: String(localized: "driver.status.accept_failed"), error.localizedDescription) }
            }
        }
    }

    func updateLocation(location: CLLocation, rideService: RideService) {
        guard let ride = rideService.activeRide else { return }
        let latLng = LatLng(latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude)
        Task {
            try? await rideService.updateDriverLocation(ride.id, location: latLng,
                                                        bearing: location.course)
        }
    }

    func markRideSeen(_ id: String) {
        seenRideIds.insert(id)
    }

    func updateStatus(_ status: RideStatus, rideService: RideService) {
        guard let ride = rideService.activeRide else { return }
        Task {
            do {
                try await rideService.updateStatus(ride.id, status: status)
                await MainActor.run { statusMessage = String(format: String(localized: "driver.status.updated"), status.rawValue) }
            } catch {
                await MainActor.run { statusMessage = String(localized: "driver.status.update_failed") }
            }
        }
    }
}

// MARK: - Main View

struct DriverHomeView: View {
    @ObservedObject var viewModel: DriverHomeViewModel
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var rideService: RideService
    @EnvironmentObject private var networkMonitor: NetworkMonitor

    @State private var selectedRide: Ride?
    @State private var incomingRide: Ride?
    @State private var showActiveRide = false
    @State private var capturedActiveRide: Ride?

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundLight.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        headerCard
                        
                        if !networkMonitor.isOnline {
                            offlineBanner
                        }

                        if viewModel.isLoading {
                            SkeletonListPlaceholder(count: 3)
                                .padding(.top, 16)
                        } else if let activeRide = rideService.activeRide, activeRide.status != .cancelled {
                            activeRideSection(ride: activeRide)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                        } else if viewModel.isOnline {
                            availableRidesSection
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                        } else {
                            offlineState
                                .padding(.top, 60)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedRide) { ride in
                DriverRideDetailView(ride: ride)
            }
        }
        .onReceive(locationService.$lastLocation) { location in
            guard let location else { return }
            viewModel.updateLocation(location: location, rideService: rideService)
        }
        .onAppear {
            locationService.startUpdating()
            if let active = rideService.activeRide,
               active.status != .completed, active.status != .cancelled {
                capturedActiveRide = active
                showActiveRide = true
            }
            checkForIncomingRide(rides: rideService.availableRides)
        }
        .onChange(of: rideService.activeRide) { _, newRide in
            guard let newRide,
                  newRide.status != .completed,
                  newRide.status != .cancelled else { return }
            withAnimation(nil) {
                if capturedActiveRide == nil { capturedActiveRide = newRide }
                showActiveRide = true
            }
        }
        .onChange(of: showActiveRide) { _, isShown in
            if !isShown { capturedActiveRide = nil }
        }
        .onChange(of: viewModel.isOnline) { _, isOnline in
            guard isOnline else { return }
            checkForIncomingRide(rides: rideService.availableRides)
        }
        .onChange(of: rideService.availableRides) { _, rides in
            checkForIncomingRide(rides: rides)
        }
        .onReceive(NotificationCenter.default.publisher(for: .TRAOpenRide)) { _ in
            if rideService.activeRide != nil { showActiveRide = true }
        }
        .fullScreenCover(item: $incomingRide) { ride in
            DriverIncomingRideSheet(
                ride: ride,
                onAccept: {
                    capturedActiveRide = rideService.activeRide
                    showActiveRide = true
                    incomingRide = nil
                },
                onDecline: {
                    viewModel.markRideSeen(ride.id)
                    incomingRide = nil
                }
            )
            .environmentObject(authService)
            .environmentObject(rideService)
            .environmentObject(networkMonitor)
        }
        .fullScreenCover(isPresented: $showActiveRide) {
            if let ride = capturedActiveRide {
                DriverActiveRideView(ride: ride)
                    .environmentObject(authService)
                    .environmentObject(rideService)
                    .environmentObject(locationService)
                    .environmentObject(networkMonitor)
            }
        }
    }

    // MARK: Header
    private var headerCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(AppColors.boltGreenLight).frame(width: 44, height: 44)
                    Text(String(viewModel.currentUser.displayName?.prefix(1) ?? "D"))
                        .font(AppFont.titleSmall()).foregroundStyle(AppColors.boltGreen)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentUser.displayName ?? String(localized: "active.ride.driver_fallback"))
                        .font(AppFont.titleSmall()).foregroundStyle(AppColors.gray900)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.isOnline ? AppColors.boltGreen : AppColors.gray300)
                            .frame(width: 8, height: 8)
                        Text(viewModel.isOnline ? String(localized: "driver.home.online") : String(localized: "driver.home.offline"))
                            .font(AppFont.labelSmall())
                            .foregroundStyle(viewModel.isOnline ? AppColors.boltGreen : AppColors.gray500)
                    }
                }

                Spacer()

                Button {} label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.gray700)
                }
                .buttonStyle(.plain)

                onlineSwitch
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            Divider()
        }
        .background(Color.white)
    }

    private var onlineSwitch: some View {
        Toggle("", isOn: .init(
            get: { viewModel.isOnline },
            set: { viewModel.toggleOnline(isOn: $0, authService: authService) }
        ))
        .tint(AppColors.boltGreen)
        .labelsHidden()
        .scaleEffect(0.85)
    }

    // MARK: Offline banner
    private var offlineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash").foregroundStyle(.white)
            Text("common.offline_banner")
                .font(AppFont.labelMedium()).foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(AppColors.errorRed)
    }

    // MARK: Available rides
    private var availableRidesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("driver.home.available_rides")
                .font(AppFont.titleSmall()).foregroundStyle(AppColors.gray500)

            if rideService.availableRides.isEmpty {
                EmptyStateView(
                    icon: "car.fill",
                    title: String(localized: "driver.home.no_rides_title"),
                    subtitle: String(localized: "driver.home.no_rides_body")
                )
                .frame(maxWidth: .infinity)
            } else {
                ForEach(rideService.availableRides) { ride in
                    AvailableRideCard(
                        ride: ride,
                        onTap: { selectedRide = ride },
                        onAccept: { viewModel.accept(ride: ride, rideService: rideService) }
                    )
                    .disabled(!networkMonitor.isOnline)
                }
            }
        }
    }

    // MARK: Active ride
    private func activeRideSection(ride: Ride) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("driver.home.active_ride")
                .font(AppFont.titleSmall()).foregroundStyle(AppColors.gray500)

            Button {
                showActiveRide = true
            } label: {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ride.destinationAddress ?? String(localized: "route.destination_fallback"))
                                .font(AppFont.titleSmall()).foregroundStyle(AppColors.gray900)
                            Text(ride.pickupAddress ?? String(localized: "route.pickup_fallback"))
                                .font(AppFont.bodySmall()).foregroundStyle(AppColors.gray500)
                        }
                        Spacer()
                        StatusChip(label: ride.status.chipLabel, color: ride.status.chipColor)
                    }

                    Divider()

                    HStack {
                        Image(systemName: "map.fill")
                            .foregroundStyle(AppColors.boltGreen)
                        Text("driver.home.open_navigation")
                            .font(AppFont.labelMedium())
                            .foregroundStyle(AppColors.boltGreen)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.gray500)
                    }
                }
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.r20))
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Offline state
    private var offlineState: some View {
        EmptyStateView(
            icon: "antenna.radiowaves.left.and.right",
            title: String(localized: "driver.home.you_are_offline"),
            subtitle: String(localized: "driver.home.go_online")
        )
    }

    // MARK: Incoming ride check
    private func checkForIncomingRide(rides: [Ride]) {
        guard viewModel.isOnline, rideService.activeRide == nil, incomingRide == nil else { return }
        if let newRide = rides.first(where: { !viewModel.seenRideIds.contains($0.id) }) {
            viewModel.markRideSeen(newRide.id)
            incomingRide = newRide
        }
    }
}

// MARK: - Available Ride Card

struct AvailableRideCard: View {
    let ride: Ride
    let onTap: () -> Void
    let onAccept: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppColors.boltGreenLight)
                            .frame(width: 44, height: 44)
                        Image(systemName: "car.fill")
                            .foregroundStyle(AppColors.boltGreen)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        routeRow(
                            dot: AppColors.boltGreen,
                            text: ride.pickupAddress ?? String(localized: "route.pickup_fallback")
                        )
                        routeRow(
                            dot: AppColors.errorRed,
                            text: ride.destinationAddress ?? String(localized: "route.destination_fallback")
                        )
                    }

                    Spacer()

                    if let scheduled = ride.scheduledAt {
                        VStack(spacing: 2) {
                            Image(systemName: "calendar").font(.system(size: 12))
                                .foregroundStyle(AppColors.gray500)
                            Text(scheduled.formatted(.dateTime.hour().minute()))
                                .font(AppFont.labelSmall()).foregroundStyle(AppColors.gray500)
                        }
                    }
                }

                Divider()

                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill").foregroundStyle(AppColors.boltGreen)
                        Text(String(format: "SRD %.2f", ride.totalFareRealtime))
                            .font(AppFont.labelMedium()).foregroundStyle(AppColors.gray700)
                    }
                    Spacer()
                    Button(action: onAccept) {
                        Text("driver.incoming.accept")
                            .font(AppFont.labelLarge())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .frame(height: 36)
                            .background(AppColors.boltGreen)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r20))
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func routeRow(dot: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(text)
                .font(AppFont.bodySmall()).foregroundStyle(AppColors.gray700)
                .lineLimit(1)
        }
    }
}

#Preview {
    DriverHomeView(
        viewModel: DriverHomeViewModel(
            container: AppContainer(),
            currentUser: User(id: "demo-driver", role: .driver, isDriverOnline: true)
        )
    )
    .environmentObject(AuthService(repository: InMemoryAuthRepository(seedUsers: [
        User(id: "demo-driver", role: .driver)
    ])))
    .environmentObject(PushService())
    .environmentObject(LocationService())
    .environmentObject(
        RideService(
            repository: InMemoryRideRepository(),
            navigationManager: NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil)),
            networkMonitor: NetworkMonitor.preview
        )
    )
    .environmentObject(NetworkMonitor.preview)
}
