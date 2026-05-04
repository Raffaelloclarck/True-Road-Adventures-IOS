import Foundation
import UserNotifications
import UIKit
import Combine
import FirebaseMessaging
#if canImport(FirebaseFirestore)
import FirebaseFirestore
import FirebaseAuth
#endif

@MainActor
final class PushService: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String?

    private let uploadURL: URL?
    var tokenProvider: (() async -> String?)?
    var onTokenRegistered: ((String) -> Void)?

    init(uploadURL: URL? = nil) {
        self.uploadURL = uploadURL
    }

    func requestAuthorization() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            let priorSettings = await center.notificationSettings()
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            let settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus
            // Only call registerForRemoteNotifications() when the user is granting
            // permission for the first time. For already-authorised sessions AppDelegate
            // registers at launch, so calling it again here is redundant and produces
            // a duplicate didFailToRegisterForRemoteNotificationsWithError on simulator.
            if granted && priorSettings.authorizationStatus == .notDetermined {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return granted
        } catch {
            print("Push auth error: \(error)")
            return false
        }
    }

    func handleDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        deviceToken = token
        Task {
            await upload(token: token)
            await storeFCMTokenInFirestore()
        }
        onTokenRegistered?(token)
    }

    func storeFCMToken() async {
        #if canImport(FirebaseFirestore)
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Requesting the FCM token before the APNS token is set produces a warning and returns nil.
        // Wait until the APNS token has been delivered via didRegisterForRemoteNotificationsWithDeviceToken.
        guard Messaging.messaging().apnsToken != nil else { return }
        guard let fcmToken = try? await Messaging.messaging().token() else { return }
        try? await Firestore.firestore().collection("users").document(uid)
            .updateData(["fcmToken": fcmToken])
        #endif
    }

    private func storeFCMTokenInFirestore() async {
        await storeFCMToken()
    }

    func handleRegistrationError(_ error: Error) {
        print("Push registration error: \(error)")
    }

    private func upload(token: String) async {
        guard let uploadURL else { return }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer = await tokenProvider?() {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        let payload: [String: String] = [
            "token": token,
            "platform": "ios"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            print("Push token upload failed: \(error)")
        }
    }
}
