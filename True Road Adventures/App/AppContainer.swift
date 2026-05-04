import Foundation
import Combine

final class AppContainer {
    let config: AppConfig
    let analytics: AnalyticsService
    let networkMonitor: NetworkMonitor
    let authRepository: AuthRepository
    let authService: AuthService
    let pushService: PushService
    let locationService: LocationService
    let paymentService: PaymentService
    let rideRepository: RideRepository
    let rideService: RideService
    let navigationManager: NavigationSessionManager
    let directionsClient: DirectionsClient
    let languageManager: LanguageManager

    private var cancellables = Set<AnyCancellable>()

    init(appMode: AppMode = .customer) {
        self.config = AppConfig.load()
        self.analytics = AnalyticsService()
        self.networkMonitor = NetworkMonitor()
        self.languageManager = LanguageManager()
        self.authRepository = FirebaseAuthRepository(appMode: appMode)
        self.authService = AuthService(repository: authRepository, languageManager: languageManager)
        self.pushService = PushService(uploadURL: config.pushUploadURL)
        self.locationService = LocationService()
        self.paymentService = PaymentService(config: config)
        self.directionsClient = DirectionsClient(apiKey: config.googleDirectionsApiKey)
        self.navigationManager = NavigationSessionManager(directionsClient: directionsClient)

        if config.useMockAPI {
            self.rideRepository = InMemoryRideRepository()
        } else {
            self.rideRepository = FirestoreRideRepository()
        }

        self.rideService = RideService(
            repository: rideRepository,
            navigationManager: navigationManager,
            networkMonitor: networkMonitor,
            analytics: analytics
        )

        pushService.onTokenRegistered = { token in
            print("Registered push token: \(token)")
        }
        pushService.tokenProvider = { [weak authService] in
            await authService?.currentToken()
        }

        // Re-attach user to ride service whenever auth state changes (login, logout, session restore).
        // Using removeDuplicates on user id prevents redundant Firestore listener restarts.
        authService.$state
            .map(\.user)
            .removeDuplicates { $0?.id == $1?.id }
            .sink { [weak rideService] user in
                Task { @MainActor [weak rideService] in
                    rideService?.attachUser(user)
                }
            }
            .store(in: &cancellables)
    }
}
