import Foundation
import Combine
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

/// Event-logger that forwards to Firebase Analytics when available.
/// Falls back to an in-memory ring buffer (useful for debug/testing).
final class AnalyticsService: ObservableObject {
    struct Event: Identifiable {
        let id = UUID()
        let name: String
        let properties: [String: String]
        let timestamp: Date
    }

    @Published private(set) var recentEvents: [Event] = []
    private let maxEvents: Int

    init(maxEvents: Int = 50) {
        self.maxEvents = maxEvents
    }

    func track(_ name: String, properties: [String: String] = [:]) {
        let event = Event(name: name, properties: properties, timestamp: .now)
        appendToBuffer(event)
        forwardToFirebase(name: name, properties: properties)
    }

    // MARK: - Private

    private func appendToBuffer(_ event: Event) {
        recentEvents.insert(event, at: 0)
        if recentEvents.count > maxEvents {
            recentEvents.removeLast(recentEvents.count - maxEvents)
        }
        #if DEBUG
        print("[Analytics] \(event.name) \(event.properties)")
        #endif
    }

    private func forwardToFirebase(name: String, properties: [String: String]) {
        #if canImport(FirebaseAnalytics)
        // Firebase Analytics event names must be ≤40 chars and contain only letters, numbers, underscores.
        let safeName = name
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .prefix(40)
            .description
        let params: [String: Any] = properties.reduce(into: [:]) { $0[$1.key] = $1.value }
        Analytics.logEvent(safeName, parameters: params.isEmpty ? nil : params)
        #endif
    }
}
