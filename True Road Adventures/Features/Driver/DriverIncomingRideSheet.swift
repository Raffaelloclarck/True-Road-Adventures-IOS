import SwiftUI
import AudioToolbox

struct DriverIncomingRideSheet: View {
    let ride: Ride
    let onAccept: () -> Void
    let onDecline: () -> Void

    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var rideService: RideService
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @Environment(\.dismiss) private var dismiss

    private let totalSeconds: Double = 15
    @State private var timeRemaining: Double = 15
    @State private var progress: Double = 1.0
    @State private var isAccepting = false
    @State private var timerTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                card
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
        }
        .onAppear {
            startTimer()
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            AudioServicesPlaySystemSound(1007)
        }
        .onDisappear { timerTask?.cancel() }
        .alert(String(localized: "driver.incoming.error_title"), isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 20) {
            timerRow
            Divider()
            routeSection
            fareRow
            Divider()
            actionButtons
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 8)
    }

    // MARK: - Timer row

    private var timerRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(AppColors.gray100, lineWidth: 5)
                    .frame(width: 52, height: 52)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        timerColor,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 52, height: 52)
                    .animation(.linear(duration: 1), value: progress)
                Text("\(Int(timeRemaining))")
                    .font(AppFont.titleSmall())
                    .foregroundStyle(timerColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("driver.incoming.new_ride")
                    .font(AppFont.titleMedium())
                    .foregroundStyle(AppColors.gray900)
                Text(String(format: String(localized: "driver.incoming.respond_seconds"), Int(timeRemaining)))
                    .font(AppFont.bodySmall())
                    .foregroundStyle(AppColors.gray500)
            }

            Spacer()
        }
    }

    private var timerColor: Color {
        if timeRemaining > 8 { return AppColors.boltGreen }
        if timeRemaining > 4 { return AppColors.warningAmber }
        return AppColors.errorRed
    }

    // MARK: - Route

    private var routeSection: some View {
        VStack(spacing: 10) {
            routeRow(
                dot: AppColors.boltGreen,
                label: String(localized: "driver.incoming.pickup"),
                address: ride.pickupAddress ?? String(localized: "driver.incoming.pickup_fallback")
            )
            HStack {
                Rectangle()
                    .fill(AppColors.gray300)
                    .frame(width: 2, height: 16)
                    .padding(.leading, 7)
                Spacer()
            }
            routeRow(
                dot: AppColors.errorRed,
                label: String(localized: "driver.incoming.destination"),
                address: ride.destinationAddress ?? String(localized: "driver.incoming.destination_fallback")
            )
            if let scheduled = ride.scheduledAt {
                HStack {
                    Rectangle()
                        .fill(AppColors.gray300)
                        .frame(width: 2, height: 16)
                        .padding(.leading, 7)
                    Spacer()
                }
                routeRow(
                    dot: AppColors.accentBlue,
                    label: String(localized: "driver.incoming.scheduled_for"),
                    address: scheduled.formatted(date: .abbreviated, time: .shortened)
                )
            }
        }
    }

    private func routeRow(dot: Color, label: String, address: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(dot)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.gray500)
                Text(address)
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(AppColors.gray900)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Fare

    private var fareRow: some View {
        HStack {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundStyle(AppColors.boltGreen)
                .font(.system(size: 20))
            Text("driver.incoming.estimated_fare")
                .font(AppFont.bodyMedium())
                .foregroundStyle(AppColors.gray700)
            Spacer()
            Text(String(format: "SRD %.2f", ride.totalFareRealtime))
                .font(AppFont.titleSmall())
                .foregroundStyle(AppColors.boltGreen)
        }
    }

    // MARK: - Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                timerTask?.cancel()
                onDecline()
                dismiss()
            } label: {
                Text("driver.incoming.decline")
                    .font(AppFont.labelLarge())
                    .foregroundStyle(AppColors.gray700)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppColors.gray100)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isAccepting)

            Button {
                guard let driverId = authService.state.user?.id else { return }
                isAccepting = true
                timerTask?.cancel()
                Task {
                    do {
                        try await rideService.acceptRide(ride.id, driverId: driverId)
                        await MainActor.run {
                            isAccepting = false
                            onAccept()
                            dismiss()
                        }
                    } catch RideService.RideActionError.offline {
                        await MainActor.run {
                            isAccepting = false
                            errorMessage = String(localized: "driver.incoming.error_offline")
                        }
                    } catch {
                        await MainActor.run {
                            isAccepting = false
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            } label: {
                Group {
                    if isAccepting {
                        ProgressView().tint(.white)
                    } else {
                        Text("driver.incoming.accept")
                            .font(AppFont.labelLarge())
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(networkMonitor.isOnline ? AppColors.boltGreen : AppColors.gray300)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!networkMonitor.isOnline || isAccepting)
        }
    }

    // MARK: - Timer logic

    private func startTimer() {
        timerTask = Task {
            while timeRemaining > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    timeRemaining = max(0, timeRemaining - 1)
                    progress = timeRemaining / totalSeconds
                }
            }
            if !Task.isCancelled {
                await MainActor.run {
                    onDecline()
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    DriverIncomingRideSheet(
        ride: Ride(
            id: "demo",
            customerId: "c1",
            pickupLocation: LatLng(latitude: 5.85, longitude: -55.2),
            destinationLocation: LatLng(latitude: 5.87, longitude: -55.18),
            pickupAddress: "Waterkant 12, Paramaribo",
            destinationAddress: "Johan Adolf Pengel Airport",
            totalFareRealtime: 62.50
        ),
        onAccept: {},
        onDecline: {}
    )
    .environmentObject(AuthService(repository: InMemoryAuthRepository(seedUsers: [
        User(id: "driver-1", role: .driver)
    ])))
    .environmentObject(
        RideService(
            repository: InMemoryRideRepository(),
            navigationManager: NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil))
        )
    )
    .environmentObject(NetworkMonitor.preview)
}
