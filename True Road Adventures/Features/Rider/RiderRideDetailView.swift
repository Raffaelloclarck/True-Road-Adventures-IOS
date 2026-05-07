import SwiftUI

struct RiderRideDetailView: View {
    let ride: Ride
    @EnvironmentObject private var rideService: RideService
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @Environment(\.dismiss) private var dismiss

    @State private var showCancelConfirm = false
    @State private var cancelError: Error? = nil
    @State private var showRatingSheet = false
    @State private var selectedScore = 5
    @State private var ratingComment = ""
    @State private var isSubmitting = false
    @State private var ratingSubmitted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapPlaceholder
                statusRow
                routeCard
                fareCard
                if showCancelButton {
                    cancelButton
                }
                if showRateButton {
                    rateButton
                }
            }
            .padding(16)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle(String(localized: "ride.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            String(localized: "ride.cancel.title"),
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "ride.cancel.confirm"), role: .destructive) { cancelRide() }
            Button(String(localized: "ride.cancel.back"), role: .cancel) {}
        } message: {
            Text("ride.cancel.message")
        }
        .sheet(isPresented: $showRatingSheet) {
            ratingSheet
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

    // MARK: - Map placeholder

    private var mapPlaceholder: some View {
        RoundedRectangle(cornerRadius: AppRadius.r16)
            .fill(AppColors.boltGreenLight)
            .frame(height: 180)
            .overlay(
                HStack(spacing: 16) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.boltGreen)
                    Rectangle()
                        .fill(AppColors.boltGreen.opacity(0.3))
                        .frame(height: 2)
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.errorRed)
                }
                .padding(.horizontal, 32)
            )
            .overlay(
                Image(systemName: "map.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppColors.boltGreen.opacity(0.15))
            )
    }

    // MARK: - Status row

    private var statusRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ride.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(AppFont.bodySmall())
                    .foregroundStyle(AppColors.gray500)
                if let scheduled = ride.scheduledAt {
                    Text(String(format: String(localized: "ride.detail.scheduled"), scheduled.formatted(date: .abbreviated, time: .shortened)))
                        .font(AppFont.bodySmall())
                        .foregroundStyle(AppColors.accentBlue)
                }
            }
            Spacer()
            StatusChip(label: ride.status.chipLabel, color: ride.status.chipColor)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    // MARK: - Route card

    private var routeCard: some View {
        VStack(spacing: 0) {
            routeRow(
                icon: "circle.fill",
                color: AppColors.boltGreen,
                title: String(localized: "route.pickup"),
                value: ride.pickupAddress ?? String(localized: "route.pickup_unknown")
            )
            Divider().padding(.leading, 52)
            routeRow(
                icon: "mappin.circle.fill",
                color: AppColors.errorRed,
                title: String(localized: "route.destination"),
                value: ride.destinationAddress ?? String(localized: "route.destination_unknown")
            )
            if ride.distanceKm > 0 {
                Divider().padding(.leading, 52)
                routeRow(
                    icon: "ruler.fill",
                    color: AppColors.gray500,
                    title: String(localized: "route.distance"),
                    value: String(format: "%.1f km", ride.distanceKm)
                )
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private func routeRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.gray500)
                Text(value)
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(AppColors.gray900)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Fare card

    private var fareCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.status == .completed ? String(localized: "fare.final_label") : String(localized: "fare.estimated_label"))
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.gray500)
                Text(fareString)
                    .font(AppFont.headlineSmall())
                    .foregroundStyle(AppColors.boltGreen)
            }

            Spacer()

            if let payment = ride.paymentStatus {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("payment.title")
                        .font(AppFont.labelSmall())
                        .foregroundStyle(AppColors.gray500)
                    Text(payment.label)
                        .font(AppFont.labelMedium())
                        .foregroundStyle(payment.labelColor)
                }
            }

            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.boltGreenLight)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    // MARK: - Cancel button

    private var cancelButton: some View {
        TRASecondaryButton(title: "ride.cancel.button", icon: "xmark") {
            showCancelConfirm = true
        }
        .disabled(!networkMonitor.isOnline)
    }

    // MARK: - Rate button

    private var rateButton: some View {
        TRAPrimaryButton(title: ratingSubmitted ? "ride.rate.submitted" : "ride.rate.button", isDisabled: ratingSubmitted) {
            showRatingSheet = true
        }
    }

    // MARK: - Rating sheet

    private var ratingSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("ride.rate.how_was_ride")
                    .font(AppFont.titleLarge())
                    .foregroundStyle(AppColors.gray900)

                Text(ride.destinationAddress ?? "")
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(AppColors.gray500)
                    .multilineTextAlignment(.center)

                starPicker

                TRATextField(
                    placeholder: "ride.rate.placeholder",
                    text: $ratingComment,
                    icon: "bubble.left"
                )
                .padding(.horizontal, 24)

                TRAPrimaryButton(
                    title: "ride.rate.submit",
                    isLoading: isSubmitting,
                    isDisabled: !networkMonitor.isOnline
                ) {
                    submitRating()
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.top, 32)
            .background(AppColors.backgroundLight)
            .navigationTitle(String(localized: "ride.rate.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.cancel_short")) { showRatingSheet = false }
                        .foregroundStyle(AppColors.gray500)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var starPicker: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    selectedScore = star
                } label: {
                    Image(systemName: star <= selectedScore ? "star.fill" : "star")
                        .font(.system(size: 36))
                        .foregroundStyle(star <= selectedScore ? AppColors.starYellow : AppColors.gray300)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.2), value: selectedScore)
            }
        }
    }

    // MARK: - Helpers

    private var fareString: String {
        let amount = ride.totalFareFinal ?? ride.totalFareRealtime
        return String(format: "SRD %.2f", amount)
    }

    private var showCancelButton: Bool {
        ride.status == .searching
    }

    private var showRateButton: Bool {
        ride.status == .completed && !ratingSubmitted
    }

    private func cancelRide() {
        Task {
            do {
                try await rideService.updateStatus(ride.id, status: .cancelled)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run { cancelError = error }
            }
        }
    }

    private func submitRating() {
        guard let currentUser = authService.state.user,
              let driverId = ride.driverId else { return }
        isSubmitting = true
        Task {
            do {
                try await rideService.submitRating(
                    rideId: ride.id,
                    fromUserId: currentUser.id,
                    toUserId: driverId,
                    score: selectedScore,
                    comment: ratingComment.isEmpty ? nil : ratingComment
                )
                await MainActor.run {
                    isSubmitting = false
                    ratingSubmitted = true
                    showRatingSheet = false
                }
            } catch {
                await MainActor.run { isSubmitting = false }
            }
        }
    }
}

// MARK: - PaymentStatus display helpers

private extension PaymentStatus {
    var label: String {
        switch self {
        case .pending: return String(localized: "payment.pending")
        case .paid:    return String(localized: "payment.paid")
        case .failed:  return String(localized: "payment.failed")
        case .cash:    return String(localized: "payment.cash")
        }
    }

    var labelColor: Color {
        switch self {
        case .pending: return AppColors.warningAmber
        case .paid:    return AppColors.successGreen
        case .failed:  return AppColors.errorRed
        case .cash:    return AppColors.gray700
        }
    }
}

#Preview {
    NavigationStack {
        RiderRideDetailView(ride: Ride(
            id: "demo",
            customerId: "c1",
            driverId: "d1",
            status: .completed,
            pickupLocation: LatLng(latitude: 5.8520, longitude: -55.2038),
            destinationLocation: LatLng(latitude: 5.8600, longitude: -55.1900),
            pickupAddress: "Henck Arronstraat 12, Paramaribo",
            destinationAddress: "Johan Adolf Pengel Airport",
            distanceKm: 8.4,
            rideSeconds: 900,
            totalFareFinal: 62.50
        ))
        .environmentObject(
            RideService(
                repository: InMemoryRideRepository(),
                navigationManager: NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil))
            )
        )
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
        .environmentObject(NetworkMonitor.preview)
    }
}
