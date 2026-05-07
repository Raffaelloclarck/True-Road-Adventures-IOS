import Combine
import Foundation

enum PushScreen: String {
    case home
    case activeRide
    case chat
    case promotions
}

struct PushNotificationIntent: Equatable {
    let rideId: String?
    let screen: PushScreen
}

@MainActor
final class PushNavigationStore: ObservableObject {
    @Published private(set) var pending: PushNotificationIntent?

    func set(_ intent: PushNotificationIntent) {
        pending = intent
    }

    func clearPending() {
        pending = nil
    }
}
