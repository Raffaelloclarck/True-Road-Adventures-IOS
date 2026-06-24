#if DRIVER
import SwiftUI
import GoogleSignIn

@main
struct DriverApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: AppContainer

    init() {
        AppDelegate.configureFirebase()
        FontRegistrar.registerFonts()
        container = AppContainer(appMode: .driver)
        appDelegate.pushService = container.pushService
        appDelegate.pushNavigationStore = container.pushNavigationStore
    }

    var body: some Scene {
        WindowGroup {
            LocaleApplierView(languageManager: container.languageManager) {
                DriverRootView(container: container)
                    .environmentObject(container.authService)
                    .environmentObject(container.pushService)
                    .environmentObject(container.locationService)
                    .environmentObject(container.rideService)
                    .environmentObject(container.networkMonitor)
                    .environmentObject(container.pushNavigationStore)
                    .environmentObject(container.discountCodeService)
                    .environmentObject(container.paymentService)
                    .environment(container.languageManager)
                    .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
            }
        }
    }
}
#endif
