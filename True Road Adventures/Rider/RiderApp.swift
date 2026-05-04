#if RIDER
import SwiftUI
import CoreText
import GoogleSignIn

@main
struct RiderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: AppContainer

    init() {
        AppDelegate.configureFirebase()
        FontRegistrar.registerFonts()
        container = AppContainer(appMode: .customer)
        appDelegate.pushService = container.pushService
    }

    var body: some Scene {
        WindowGroup {
            LocaleApplierView(languageManager: container.languageManager) {
                RiderRootView(container: container)
                    .environmentObject(container.authService)
                    .environmentObject(container.pushService)
                    .environmentObject(container.locationService)
                    .environmentObject(container.rideService)
                    .environmentObject(container.networkMonitor)
                    .environment(container.languageManager)
                    .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
            }
        }
    }
}
#endif
