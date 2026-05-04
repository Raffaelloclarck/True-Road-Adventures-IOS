import SwiftUI
import CoreLocation

struct DriverRootView: View {
    let container: AppContainer
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var rideService: RideService
    @EnvironmentObject private var locationService: LocationService

    @State private var showSplash = true
    @State private var permissionsCompleted: Bool = false

    var body: some View {
        Group {
            if showSplash {
                DriverSplashView {
                    withAnimation { showSplash = false }
                }
            } else if let user = authService.state.user {
                if !user.hasCompletedOnboarding {
                    OnboardingView(pages: OnboardingPage.driverPages) {
                        Task { await authService.completeOnboarding() }
                    }
                } else if !user.isApproved {
                    DriverPendingApprovalView()
                } else if permissionsCompleted || hasRequiredPermissions {
                    DriverTabView(container: container, currentUser: user)
                } else {
                    PermissionsOnboardingView(isDriver: true) {
                        withAnimation { permissionsCompleted = true }
                    }
                }
            } else {
                AuthFlowView(appMode: .driver)
            }
        }
        .onChange(of: authService.state.user) { _, newUser in
            rideService.attachUser(newUser)
            if newUser != nil {
                Task {
                    // Request permission (no-op if already granted/denied) so
                    // registerForRemoteNotifications() is always called and the
                    // APNS token is available before we try to store the FCM token.
                    _ = await container.pushService.requestAuthorization()
                    await container.pushService.storeFCMToken()
                }
            }
        }
    }

    private var hasRequiredPermissions: Bool {
        let status = locationService.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }
}
