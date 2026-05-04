import SwiftUI

struct RideHistoryView: View {
    let role: UserRole
    @EnvironmentObject private var rideService: RideService
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var authService: AuthService

    @State private var selectedFilter: RideFilter = .all
    @State private var showRideRequest = false

    private var rides: [Ride] {
        let all = role == .customer ? rideService.customerHistory : rideService.driverHistory
        switch selectedFilter {
        case .all:       return all
        case .scheduled: return all.filter {
            $0.scheduledAt != nil && $0.status != .completed && $0.status != .cancelled
        }
        case .completed: return all.filter { $0.status == .completed }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider()

                if rides.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "car.fill",
                        title: String(localized: "ride_history.empty.title"),
                        subtitle: String(localized: "ride_history.empty.body"),
                        actionTitle: role == .customer ? "ride_history.empty.cta" : nil
                    ) {
                        showRideRequest = true
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(rides) { ride in
                                NavigationLink(value: ride) {
                                    RideHistoryCard(ride: ride, role: role)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(AppColors.backgroundLight)
            .navigationTitle(Text("ride_history.title"))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Ride.self) { ride in
                RiderRideDetailView(ride: ride)
            }
            .fullScreenCover(isPresented: $showRideRequest) {
                RiderRideRequestView(scheduledAt: nil)
                    .environmentObject(rideService)
                    .environmentObject(networkMonitor)
                    .environmentObject(locationService)
                    .environmentObject(authService)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(RideFilter.allCases, id: \.self) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    Text(filter.label)
                        .font(AppFont.labelMedium())
                        .foregroundStyle(selectedFilter == filter ? AppColors.boltGreen : AppColors.gray500)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(
                            selectedFilter == filter
                            ? Rectangle()
                                .fill(AppColors.boltGreen)
                                .frame(height: 2)
                                .frame(maxWidth: .infinity)
                                .offset(y: 10)
                                .padding(.horizontal, 12)
                            : nil,
                            alignment: .bottom
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct RideHistoryCard: View {
    let ride: Ride
    let role: UserRole

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ride.destinationAddress ?? String(localized: "ride_history.destination.unknown"))
                        .font(AppFont.titleSmall())
                        .foregroundStyle(AppColors.gray900)
                    Text(ride.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(AppFont.bodySmall())
                        .foregroundStyle(AppColors.gray500)
                }
                Spacer()
                StatusChip(label: ride.status.chipLabel, color: ride.status.chipColor)
            }

            Divider()

            HStack {
                let displayPrice: Double = ride.totalFareFinal ?? ride.totalFareRealtime
                if displayPrice > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundStyle(AppColors.boltGreen)
                        Text(String(format: "SRD %.2f", displayPrice))
                            .font(AppFont.labelMedium())
                            .foregroundStyle(AppColors.gray700)
                    }
                }

                Spacer()

                if let scheduled = ride.scheduledAt {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.gray500)
                        Text(scheduled.formatted(date: .abbreviated, time: .shortened))
                            .font(AppFont.labelSmall())
                            .foregroundStyle(AppColors.gray500)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.gray300)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

enum RideFilter: CaseIterable {
    case all, scheduled, completed

    var label: LocalizedStringKey {
        switch self {
        case .all:       return "ride_history.filter.all"
        case .scheduled: return "ride_history.filter.scheduled"
        case .completed: return "ride_history.filter.completed"
        }
    }
}

#Preview {
    RideHistoryView(role: .customer)
        .environmentObject(
            RideService(
                repository: InMemoryRideRepository(),
                navigationManager: NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil))
            )
        )
}
