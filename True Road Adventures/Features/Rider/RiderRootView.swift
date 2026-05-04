import SwiftUI
import CoreLocation

struct RiderRootView: View {
    let container: AppContainer
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var rideService: RideService
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var pushService: PushService

    @State private var showSplash = true
    @State private var permissionsCompleted: Bool = false

    var body: some View {
        Group {
            if showSplash {
                SplashView {
                    withAnimation { showSplash = false }
                }
            } else if let user = authService.state.user {
                if user.role == .admin {
                    AdminTabView(container: container, currentUser: user)
                } else if !user.hasCompletedOnboarding {
                    OnboardingView(pages: OnboardingPage.riderPages) {
                        Task { await authService.completeOnboarding() }
                    }
                } else if permissionsCompleted || hasRequiredPermissions {
                    RiderTabView(container: container, currentUser: user)
                } else {
                    PermissionsOnboardingView {
                        withAnimation { permissionsCompleted = true }
                    }
                }
            } else {
                AuthFlowView(appMode: .customer)
            }
        }
        .onChange(of: authService.state.user) { _, newUser in
            rideService.attachUser(newUser)
            if newUser != nil {
                Task {
                    _ = await pushService.requestAuthorization()
                    await pushService.storeFCMToken()
                }
            }
        }
    }

    private var hasRequiredPermissions: Bool {
        let status = locationService.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }
}
