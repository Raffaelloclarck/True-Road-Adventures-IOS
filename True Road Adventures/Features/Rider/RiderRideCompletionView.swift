import SwiftUI

struct RiderRideCompletionView: View {
    let ride: Ride
    let driverUser: User?
    let onDismiss: () -> Void

    @EnvironmentObject private var rideService: RideService
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var paymentService: PaymentService

    @State private var selectedScore: Int = 5
    @State private var comment: String = ""
    @State private var selectedChips: Set<String> = []
    @State private var isSubmitting = false
    @State private var isProcessingPayment = false
    @State private var paymentBanner: String?

    private let feedbackChipKeys = [
        "completion.feedback.friendly",
        "completion.feedback.punctual",
        "completion.feedback.clean_car",
        "completion.feedback.good_driver"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                completionHeader
                if let banner = paymentBanner {
                    paymentStatusBanner(banner)
                }
                fareCard
                if ride.appliedDiscountCode != nil {
                    discountRow
                }
                driverCard
                ratingSection
                quickFeedbackChips
                TRATextField(
                    placeholder: "ride.rate.placeholder",
                    text: $comment,
                    icon: "text.bubble"
                )
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    TRAPrimaryButton(
                        title: "completion.submit_rating",
                        isLoading: isSubmitting,
                        isDisabled: !networkMonitor.isOnline
                    ) {
                        submitRating()
                    }
                    .padding(.horizontal, 20)

                    Button {
                        onDismiss()
                    } label: {
                        Text("completion.skip")
                            .font(AppFont.labelMedium())
                            .foregroundStyle(AppColors.gray500)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)
            }
            .padding(.top, 24)
        }
        .background(AppColors.backgroundLight)
        .ignoresSafeArea(edges: .bottom)
        .task { await processCardPaymentIfNeeded() }
    }

    private func paymentStatusBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            if isProcessingPayment {
                ProgressView().scaleEffect(0.85)
            } else {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(AppColors.boltGreen)
            }
            Text(text)
                .font(AppFont.labelMedium())
                .foregroundStyle(AppColors.gray700)
            Spacer()
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r12))
        .padding(.horizontal, 20)
    }

    private func processCardPaymentIfNeeded() async {
        guard ride.paymentMethod == .card,
              ride.paymentStatus == .pending,
              let amount = ride.totalFareFinal, amount > 0 else { return }

        await MainActor.run {
            isProcessingPayment = true
            paymentBanner = String(localized: "payment.processing")
        }
        do {
            try await paymentService.captureRidePayment(rideId: ride.id, amount: amount)
            await MainActor.run {
                paymentBanner = String(localized: "payment.paid")
            }
        } catch {
            await MainActor.run {
                paymentBanner = error.localizedDescription
            }
        }
        await MainActor.run { isProcessingPayment = false }
    }

    // MARK: - Completion header

    private var riderFirstName: String {
        let full = authService.state.user?.displayName ?? ""
        return full.components(separatedBy: " ").first ?? full
    }

    private var completionHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppColors.boltGreenLight)
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(AppColors.boltGreen)
            }

            VStack(spacing: 6) {
                if !riderFirstName.isEmpty {
                    Text(String(format: String(localized: "completion.thank_you_name"), riderFirstName))
                        .font(AppFont.headlineSmall())
                        .foregroundStyle(AppColors.gray900)
                } else {
                    Text("completion.ride_completed")
                        .font(AppFont.headlineSmall())
                        .foregroundStyle(AppColors.gray900)
                }

                Text("completion.review_encouragement")
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(AppColors.boltGreen)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if let destination = ride.destinationAddress {
                    Text(destination)
                        .font(AppFont.bodySmall())
                        .foregroundStyle(AppColors.gray500)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Fare card

    private var fareCard: some View {
        HStack(spacing: 0) {
            fareMetric(
                value: String(format: "SRD %.2f", ride.totalFareFinal ?? ride.totalFareRealtime),
                label: String(localized: "fare.final_label"),
                valueColor: AppColors.boltGreen
            )
            Divider().frame(height: 44)
            fareMetric(
                value: String(format: "%.1f km", ride.distanceKm),
                label: String(localized: "route.distance"),
                valueColor: AppColors.gray900
            )
            Divider().frame(height: 44)
            fareMetric(
                value: formatDuration(ride.rideSeconds),
                label: String(localized: "completion.ride_time"),
                valueColor: AppColors.gray900
            )
        }
        .padding(.vertical, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 20)
    }

    // MARK: - Discount row

    private var discountRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppColors.boltGreenLight)
                    .frame(width: 36, height: 36)
                Image(systemName: "tag.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.boltGreen)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Kortingscode toegepast")
                    .font(AppFont.labelMedium())
                    .foregroundStyle(AppColors.gray500)
                Text(ride.appliedDiscountCode ?? "")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(AppColors.gray900)
            }
            Spacer()
            if let amount = ride.discountAmount, amount > 0 {
                Text(String(format: "− SRD %.2f", amount))
                    .font(AppFont.titleSmall())
                    .foregroundStyle(AppColors.boltGreen)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 20)
    }

    private func fareMetric(value: String, label: String, valueColor: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppFont.titleSmall())
                .foregroundStyle(valueColor)
                .monospacedDigit()
            Text(label)
                .font(AppFont.labelSmall())
                .foregroundStyle(AppColors.gray500)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Driver card

    private var driverCard: some View {
        HStack(spacing: 14) {
            driverAvatar

            VStack(alignment: .leading, spacing: 4) {
                Text(driverUser?.displayName ?? String(localized: "active.ride.driver_fallback"))
                    .font(AppFont.titleSmall())
                    .foregroundStyle(AppColors.gray900)
                if let vehicle = driverUser?.vehicle {
                    Text([vehicle.vehicleType, vehicle.licensePlate]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                        .font(AppFont.labelSmall())
                        .foregroundStyle(AppColors.gray500)
                }
            }

            Spacer()

                Text("completion.your_driver")
                .font(AppFont.labelSmall())
                .foregroundStyle(AppColors.gray500)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AppColors.backgroundCard)
                .clipShape(Capsule())
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 20)
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
                default:
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

    // MARK: - Rating section

    private var ratingSection: some View {
        VStack(spacing: 12) {
            Text("ride.rate.how_was_ride")
                .font(AppFont.titleMedium())
                .foregroundStyle(AppColors.gray900)

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                            selectedScore = star
                        }
                    } label: {
                        Image(systemName: star <= selectedScore ? "star.fill" : "star")
                            .font(.system(size: 38))
                            .foregroundStyle(star <= selectedScore ? AppColors.starYellow : AppColors.gray300)
                            .scaleEffect(star == selectedScore ? 1.15 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: selectedScore)
                }
            }

            Text(scoreLabel)
                .font(AppFont.labelMedium())
                .foregroundStyle(AppColors.gray500)
                .animation(.easeInOut(duration: 0.15), value: selectedScore)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 20)
    }

    private var scoreLabel: String {
        switch selectedScore {
        case 1: return String(localized: "score.1")
        case 2: return String(localized: "score.2")
        case 3: return String(localized: "score.3")
        case 4: return String(localized: "score.4")
        default: return String(localized: "score.5")
        }
    }

    // MARK: - Quick feedback chips

    private var quickFeedbackChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(feedbackChipKeys, id: \.self) { chipKey in
                    let chipText = String(localized: String.LocalizationValue(chipKey))
                    let isSelected = selectedChips.contains(chipKey)
                    Button {
                        withAnimation(.spring(response: 0.2)) {
                            if isSelected {
                                selectedChips.remove(chipKey)
                                removeFromComment(chipText)
                            } else {
                                selectedChips.insert(chipKey)
                                appendToComment(chipText)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(chipText)
                                .font(AppFont.labelMedium())
                        }
                        .foregroundStyle(isSelected ? .white : AppColors.boltGreen)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isSelected
                            ? AppColors.boltGreen
                            : AppColors.boltGreenLight
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Helpers

    private func appendToComment(_ chip: String) {
        let trimmed = comment.trimmingCharacters(in: .whitespaces)
        comment = trimmed.isEmpty ? chip : trimmed + ", " + chip
    }

    private func removeFromComment(_ chip: String) {
        let parts = comment
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0 != chip }
        comment = parts.joined(separator: ", ")
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes >= 60 {
            return "\(minutes / 60)u \(minutes % 60)m"
        }
        return "\(max(1, minutes)) min"
    }

    // MARK: - Submit

    private func submitRating() {
        guard let fromUserId = authService.state.user?.id,
              let toUserId = ride.driverId else {
            onDismiss()
            return
        }
        isSubmitting = true
        Task {
            try? await rideService.submitRating(
                rideId: ride.id,
                fromUserId: fromUserId,
                toUserId: toUserId,
                score: selectedScore,
                comment: comment.trimmingCharacters(in: .whitespaces).isEmpty ? nil : comment.trimmingCharacters(in: .whitespaces)
            )
            await MainActor.run {
                isSubmitting = false
                onDismiss()
            }
        }
    }
}

#Preview {
    RiderRideCompletionView(
        ride: Ride(
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
        ),
        driverUser: User(id: "d1", email: "driver@tra.com", displayName: "Mohammed A.", role: .driver),
        onDismiss: {}
    )
    .environmentObject(
        RideService(
            repository: InMemoryRideRepository(),
            navigationManager: NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil))
        )
    )
    .environmentObject(AuthService(repository: InMemoryAuthRepository()))
    .environmentObject(NetworkMonitor.preview)
}
