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
                    .environment(container.languageManager)
                    .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
            }
        }
    }
}
#endif
