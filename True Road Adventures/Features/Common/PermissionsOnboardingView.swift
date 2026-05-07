import SwiftUI
import CoreLocation
import UserNotifications

struct PermissionsOnboardingView: View {
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var pushService: PushService
    var isDriver: Bool = false
    var onComplete: () -> Void

    @State private var locationGranted = false
    @State private var notificationsGranted = false
    @State private var currentStep = 0

    var body: some View {
        ZStack {
            AppColors.boltGreenDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                logoSection
                    .padding(.bottom, 48)

                if currentStep == 0 {
            permissionCard(
                    icon: "location.fill",
                    title: "permissions.location.title",
                    description: "permissions.location.body",
                    buttonTitle: "permissions.location.cta",
                    action: requestLocation
                )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else {
                    permissionCard(
                        icon: "bell.fill",
                        title: "permissions.notifications.title",
                        description: "permissions.notifications.body",
                        buttonTitle: "permissions.notifications.cta",
                        action: requestNotifications
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }

                stepIndicator
                    .padding(.top, 32)

                skipButton
                    .padding(.top, 16)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            checkExistingPermissions()
        }
    }

    private var logoSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "car.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(AppColors.boltGreen)
            }
            Text("permissions.title")
                .font(AppFont.titleLarge())
                .foregroundStyle(.white)
            Text("permissions.subtitle")
                .font(AppFont.bodyMedium())
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func permissionCard(
        icon: String,
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        buttonTitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppColors.boltGreen.opacity(0.2))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundStyle(AppColors.boltGreen)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(AppFont.titleLarge())
                    .foregroundStyle(.white)
                Text(description)
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            TRAPrimaryButton(title: buttonTitle, action: action)
        }
        .padding(28)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r24))
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<2) { step in
                Capsule()
                    .fill(currentStep == step ? AppColors.boltGreen : .white.opacity(0.3))
                    .frame(width: currentStep == step ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: currentStep)
            }
        }
    }

    private var skipButton: some View {
        Button {
            advanceOrComplete()
        } label: {
            Text("permissions.skip")
                .font(AppFont.labelMedium())
                .foregroundStyle(.white.opacity(0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private func checkExistingPermissions() {
        let status = locationService.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationGranted = true
            // Permission was already granted (e.g. returning user). Start updates
            // immediately so GPS is ready before the home screen appears.
            locationService.startUpdating()
            currentStep = 1
        }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                if settings.authorizationStatus == .authorized {
                    notificationsGranted = true
                    if locationGranted { onComplete() }
                }
            }
        }
    }

    private func requestLocation() {
        if isDriver {
            locationService.requestAlwaysPermission()
        } else {
            locationService.requestPermission()
        }
        locationService.startUpdating()
        locationGranted = true
        withAnimation(.spring(response: 0.4)) { currentStep = 1 }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                notificationsGranted = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                onComplete()
            }
        }
    }

    private func advanceOrComplete() {
        if currentStep == 0 {
            withAnimation(.spring(response: 0.4)) { currentStep = 1 }
        } else {
            onComplete()
        }
    }
}

#Preview {
    PermissionsOnboardingView(onComplete: {})
        .environmentObject(LocationService())
        .environmentObject(PushService(uploadURL: nil))
}
