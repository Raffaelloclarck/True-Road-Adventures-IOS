import SwiftUI

struct RiderTabView: View {
    let container: AppContainer
    let currentUser: User

    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var rideService: RideService
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var pushNavigationStore: PushNavigationStore

    @State private var selectedTab: RiderTab = .home
    @State private var isDrawerOpen = false
    @State private var profileSheetDestination: ProfileDestination? = nil

    var body: some View {
        ZStack(alignment: .leading) {
            tabContent

            if isDrawerOpen {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            isDrawerOpen = false
                        }
                    }

                RiderDrawerView(
                    onNavigate: { destination in
                        handleDrawerNavigation(destination)
                    },
                    onClose: {
                        withAnimation(.spring(response: 0.3)) {
                            isDrawerOpen = false
                        }
                    }
                )
                .transition(.move(edge: .leading))
            }
        }
        .environment(\.openDrawer, {
            withAnimation(.spring(response: 0.3)) {
                isDrawerOpen = true
            }
        })
        .sheet(item: $profileSheetDestination) { dest in
            NavigationStack {
                profileDestinationView(dest)
            }
        }
        .onChange(of: pushNavigationStore.pending) { _, intent in
            guard intent != nil else { return }
            withAnimation(.spring(response: 0.35)) { selectedTab = .home }
        }
        .onChange(of: rideService.activeRide) { oldRide, newRide in
            // When an active ride disappears (cancelled or completed) redirect to home
            // so the rider lands on the search screen ready for the next ride.
            if oldRide != nil, newRide == nil, selectedTab != .home {
                withAnimation(.spring(response: 0.35)) { selectedTab = .home }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .home:
                RiderHomeView(
                    viewModel: RiderHomeViewModel(
                        container: container,
                        currentUser: currentUser
                    )
                )
            case .rides:
                RideHistoryView(role: .customer)
            case .profile:
                RiderProfileView(currentUser: currentUser)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RiderWhiteTabBar(selectedTab: $selectedTab)
        }
        .onAppear { hideNativeTabBar() }
    }

    @ViewBuilder
    private func profileDestinationView(_ dest: ProfileDestination) -> some View {
        switch dest {
        case .personalInfo:  RiderPersonalInfoView()
        case .payment:       RiderPaymentInfoView()
        case .savedPlaces:   RiderSavedPlacesView()
        case .preferences:   RiderPreferencesView()
        case .promotions:    RiderPromotionsView(currentUser: currentUser)
        case .safety:        RiderSafetyInfoView()
        case .support:       SupportTopicView()
        case .about:         AboutView()
        }
    }

    private func handleDrawerNavigation(_ destination: RiderDrawerDestination) {
        withAnimation(.spring(response: 0.3)) { isDrawerOpen = false }
        switch destination {
        case .home:
            selectedTab = .home
        case .rides:
            selectedTab = .rides
        case .profile:
            selectedTab = .profile
        case .savedPlaces:
            selectedTab = .profile
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                profileSheetDestination = .savedPlaces
            }
        case .payment:
            selectedTab = .profile
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                profileSheetDestination = .payment
            }
        case .promotions:
            selectedTab = .profile
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                profileSheetDestination = .promotions
            }
        case .safety:
            selectedTab = .profile
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                profileSheetDestination = .safety
            }
        case .support:
            selectedTab = .profile
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                profileSheetDestination = .support
            }
        case .about:
            selectedTab = .profile
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                profileSheetDestination = .about
            }
        case .logout:
            authService.logout()
        }
    }

    private func hideNativeTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().isHidden = true
    }
}

// MARK: - White Tab Bar

private struct RiderWhiteTabBar: View {
    @Binding var selectedTab: RiderTab

    private let tabs: [(tab: RiderTab, icon: String, label: LocalizedStringKey)] = [
        (.home,    "house.fill",   "tab.home"),
        (.rides,   "clock.fill",   "tab.rides"),
        (.profile, "person.fill",  "tab.profile"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                ForEach(tabs, id: \.tab) { item in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            selectedTab = item.tab
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.icon)
                                .font(.system(size: 22, weight: .semibold))
                            Text(item.label)
                                .font(AppFont.labelSmall())
                        }
                        .foregroundStyle(selectedTab == item.tab ? AppColors.boltGreen : AppColors.gray300)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selectedTab)
                }
            }
            .background(Color.white)
        }
        .background(Color.white)
    }
}

enum RiderTab: String {
    case home, rides, profile
}

// MARK: - ProfileDestination Identifiable conformance
extension ProfileDestination: Identifiable {
    public var id: String {
        switch self {
        case .personalInfo: return "personalInfo"
        case .payment:      return "payment"
        case .savedPlaces:  return "savedPlaces"
        case .preferences:  return "preferences"
        case .promotions:   return "promotions"
        case .safety:       return "safety"
        case .support:      return "support"
        case .about:        return "about"
        }
    }
}

// MARK: - OpenDrawer Environment Key
struct OpenDrawerKey: EnvironmentKey {
    static let defaultValue: (() -> Void) = {}
}

extension EnvironmentValues {
    var openDrawer: () -> Void {
        get { self[OpenDrawerKey.self] }
        set { self[OpenDrawerKey.self] = newValue }
    }
}

#Preview {
    RiderTabView(
        container: AppContainer(),
        currentUser: User(id: "demo", email: "demo@test.com", displayName: "Demo User", role: .customer)
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
