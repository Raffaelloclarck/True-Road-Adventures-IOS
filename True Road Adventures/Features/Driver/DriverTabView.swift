import SwiftUI

struct DriverTabView: View {
    let container: AppContainer
    let currentUser: User

    @EnvironmentObject private var pushNavigationStore: PushNavigationStore
    @State private var selectedTab: DriverTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(String(localized: "tab.home"), systemImage: "house.fill", value: DriverTab.home) {
                DriverHomeView(
                    viewModel: DriverHomeViewModel(
                        container: container,
                        currentUser: currentUser
                    )
                )
            }

            Tab(String(localized: "tab.rides"), systemImage: "clock.fill", value: DriverTab.rides) {
                RideHistoryView(role: .driver)
            }

            Tab(String(localized: "tab.profile"), systemImage: "person.fill", value: DriverTab.profile) {
                DriverProfileView(currentUser: currentUser)
            }
        }
        .tint(AppColors.boltGreen)
        .onAppear { applyTabBarAppearance() }
        .onChange(of: pushNavigationStore.pending) { _, intent in
            guard intent != nil else { return }
            withAnimation(.spring(response: 0.35)) { selectedTab = .home }
        }
    }

    private func applyTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(AppColors.boltGreen)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(AppColors.boltGreen)
        ]
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(AppColors.gray300)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(AppColors.gray300)
        ]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

enum DriverTab: String {
    case home, rides, profile
}

#Preview {
    DriverTabView(
        container: AppContainer(),
        currentUser: User(id: "demo-driver", email: "driver@test.nl",
                          displayName: "Demo Chauffeur", role: .driver)
    )
    .environmentObject(AuthService(repository: InMemoryAuthRepository()))
    .environmentObject(
        RideService(
            repository: InMemoryRideRepository(),
            navigationManager: NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil))
        )
    )
    .environmentObject(LocationService())
    .environmentObject(NetworkMonitor.preview)
}
