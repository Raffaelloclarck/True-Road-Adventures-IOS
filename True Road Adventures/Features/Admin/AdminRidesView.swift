import SwiftUI

struct AdminRidesView: View {
    @EnvironmentObject private var rideService: RideService

    @State private var selectedFilter: RideFilter = .all

    private var rides: [Ride] {
        switch selectedFilter {
        case .all:       return rideService.adminRides
        case .scheduled: return rideService.adminRides.filter {
            $0.scheduledAt != nil && $0.status != .completed && $0.status != .cancelled
        }
        case .completed: return rideService.adminRides.filter { $0.status == .completed }
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
                        subtitle: String(localized: "ride_history.empty.body")
                    )
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(rides) { ride in
                                RideHistoryCard(ride: ride, role: .customer)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(AppColors.backgroundLight)
            .navigationTitle(Text("admin.rides.title"))
            .navigationBarTitleDisplayMode(.large)
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

#Preview {
    AdminRidesView()
        .environmentObject(
            RideService(
                repository: InMemoryRideRepository(),
                navigationManager: NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil))
            )
        )
}
