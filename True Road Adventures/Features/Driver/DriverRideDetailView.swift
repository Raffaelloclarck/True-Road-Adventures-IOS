import SwiftUI

struct DriverRideDetailView: View {
    let ride: Ride
    @EnvironmentObject private var rideService: RideService
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @Environment(\.dismiss) private var dismiss

    @State private var customerRating: Double?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapPreview
                rideDetailsCard
                customerCard
                fareCard
                actionButtons
            }
            .padding(16)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle(String(localized: "ride.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let ratings = await authService.fetchRatings(for: ride.customerId)
            if !ratings.isEmpty {
                customerRating = Double(ratings.map(\.score).reduce(0, +)) / Double(ratings.count)
            }
        }
    }

    private var mapPreview: some View {
        RoundedRectangle(cornerRadius: AppRadius.r16)
            .fill(AppColors.boltGreenLight)
            .frame(height: 180)
            .overlay(
                Image(systemName: "map.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppColors.boltGreen.opacity(0.4))
            )
    }

    private var rideDetailsCard: some View {
        VStack(spacing: 0) {
            detailRow(icon: "circle.fill", color: AppColors.boltGreen,
                      title: String(localized: "route.pickup"),
                      value: ride.pickupAddress ?? String(localized: "common.unknown"))
            Divider().padding(.leading, 52)
            detailRow(icon: "mappin.circle.fill", color: AppColors.errorRed,
                      title: String(localized: "route.destination"),
                      value: ride.destinationAddress ?? String(localized: "common.unknown"))
            if let scheduled = ride.scheduledAt {
                Divider().padding(.leading, 52)
                detailRow(icon: "calendar.circle.fill", color: AppColors.accentBlue,
                          title: String(localized: "route.scheduled_for"),
                          value: scheduled.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private func detailRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.labelSmall()).foregroundStyle(AppColors.gray500)
                Text(value).font(AppFont.bodyMedium()).foregroundStyle(AppColors.gray900)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var customerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(AppColors.boltGreenLight).frame(width: 44, height: 44)
                Image(systemName: "person.fill").foregroundStyle(AppColors.boltGreen)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("ride.detail.passenger").font(AppFont.titleSmall()).foregroundStyle(AppColors.gray900)
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(AppColors.starYellow)
                    Text(customerRating.map { String(format: "%.1f", $0) } ?? "–")
                        .font(AppFont.labelSmall()).foregroundStyle(AppColors.gray500)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private var fareCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("fare.estimated_label").font(AppFont.labelSmall()).foregroundStyle(AppColors.gray500)
                Text(ride.totalFareFinal.map { String(format: "SRD %.2f", $0) }
                     ?? String(format: "SRD %.2f", ride.totalFareRealtime))
                    .font(AppFont.headlineSmall()).foregroundStyle(AppColors.boltGreen)
            }
            Spacer()
            Image(systemName: "dollarsign.circle.fill").font(.system(size: 32))
                .foregroundStyle(AppColors.boltGreenLight)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            TRAPrimaryButton(
                title: "ride.detail.accept",
                isDisabled: !networkMonitor.isOnline
            ) {
                Task {
                    guard let driverId = authService.state.user?.id else { return }
                    try? await rideService.acceptRide(ride.id, driverId: driverId)
                    dismiss()
                }
            }
            TRASecondaryButton(title: "driver.incoming.decline") { dismiss() }
        }
    }
}

#Preview {
    NavigationStack {
        DriverRideDetailView(ride: Ride(
            id: "demo", customerId: "c1",
            pickupLocation: LatLng(latitude: 52.37, longitude: 4.89),
            destinationLocation: LatLng(latitude: 52.31, longitude: 4.76),
            pickupAddress: "Dam Square",
            destinationAddress: "Schiphol Airport"
        ))
        .environmentObject(
            RideService(repository: InMemoryRideRepository(),
                        navigationManager: NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil)))
        )
        .environmentObject(AuthService(repository: InMemoryAuthRepository(seedUsers: [
            User(id: "preview-driver", role: .driver)
        ])))
        .environmentObject(NetworkMonitor.preview)
    }
}
