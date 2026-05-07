import SwiftUI
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging
import GoogleSignIn
#if canImport(GoogleMaps)
import GoogleMaps
#endif

final class AppDelegate: NSObject, UIApplicationDelegate {
    var pushService: PushService?
    var pushNavigationStore: PushNavigationStore?

    // Swift static `let` runs once the class is first referenced — this fires
    // before UIKit constructs the delegate, which silences the
    // "[I-COR000003] The default Firebase app has not yet been configured" warning
    // that otherwise appears when a Firebase SDK's +load method runs first.
    private static let _earlyFirebaseSetup: Void = { AppDelegate.configureFirebase() }()

    override init() {
        _ = AppDelegate._earlyFirebaseSetup  // ensure the initializer ran
        super.init()
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        AppDelegate.configureFirebase() // no-op if already configured

        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String {
            #if canImport(GoogleMaps)
            GMSServices.provideAPIKey(apiKey)
            #endif
        }

        UNUserNotificationCenter.current().delegate = self

        // Always register for remote notifications at launch so the APNS token
        // is refreshed every session. Without this, storeFCMToken() silently
        // fails because Messaging.apnsToken is nil when push was already granted
        // in a previous session but registerForRemoteNotifications() was not called.
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }

        return true
    }

    // MARK: - Firebase

    /// Configures Firebase exactly once. Safe to call multiple times — subsequent calls are no-ops.
    /// Must be invoked before any Firebase service (Firestore, Auth, etc.) is first accessed.
    static func configureFirebase() {
        if FirebaseApp.app() == nil {
            #if RIDER
            let candidates: [(name: String, subdir: String?)] = [
                ("GoogleService-Info-Rider", nil),
                ("GoogleService-Info-Rider", "Rider"),
                ("GoogleService-Info",       nil),
            ]
            #elseif DRIVER
            let candidates: [(name: String, subdir: String?)] = [
                ("GoogleService-Info-Driver", nil),
                ("GoogleService-Info-Driver", "Driver"),
                ("GoogleService-Info",        nil),
            ]
            #else
            let candidates: [(name: String, subdir: String?)] = [
                ("GoogleService-Info", nil),
            ]
            #endif

            // Walk through candidate paths in order; use the first one that resolves
            // to a valid FirebaseOptions. This handles flat bundle copies, Xcode
            // Synchronized Folders (which preserve the folder hierarchy), and
            // single-plist projects.
            let options = candidates.lazy.compactMap { candidate -> FirebaseOptions? in
                guard let path = Bundle.main.path(
                    forResource: candidate.name,
                    ofType: "plist",
                    inDirectory: candidate.subdir
                ) else { return nil }
                return FirebaseOptions(contentsOfFile: path)
            }.first

            if let options {
                FirebaseApp.configure(options: options)
            } else {
                assertionFailure(
                    "[TRA] No GoogleService-Info plist found in the app bundle. " +
                    "Add the correct GoogleService-Info plist to the target and ensure " +
                    "it is included in the 'Copy Bundle Resources' build phase."
                )
                FirebaseApp.configure()
            }
        }

        // Always configure Google Sign-In — this must run even when Firebase was
        // already initialised by the early Obj-C +load method, which does not set
        // up GIDSignIn. Skipping this causes a crash: "No active configuration."
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        pushService?.handleDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        pushService?.handleRegistrationError(error)
    }

    // Required when FirebaseAppDelegateProxyEnabled = NO so FCM can process
    // data-only messages and background notification refreshes.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Messaging.messaging().appDidReceiveMessage(userInfo)
        completionHandler(.newData)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show notification banners even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }

    /// Handle notification taps — route to the correct screen via PushNavigationStore.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Messaging.messaging().appDidReceiveMessage(userInfo)
        let screenStr = userInfo["screen"] as? String ?? "home"
        let screen = PushScreen(rawValue: screenStr) ?? .home
        let rideId = userInfo["rideId"] as? String
        let intent = PushNotificationIntent(rideId: rideId, screen: screen)
        Task { @MainActor [weak self] in
            self?.pushNavigationStore?.set(intent)
        }
        completionHandler()
    }
}
