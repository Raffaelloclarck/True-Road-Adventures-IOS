import Foundation
import Observation

@Observable
final class LanguageManager {
    private static let storageKey = "app_language"

    private(set) var locale: Locale
    private(set) var currentCode: String

    init() {
        let code = UserDefaults.standard.string(forKey: Self.storageKey) ?? "nl"
        self.currentCode = code
        self.locale = Locale(identifier: code)
    }

    func apply(_ code: String) {
        guard !code.isEmpty else { return }
        UserDefaults.standard.set(code, forKey: Self.storageKey)
        currentCode = code
        locale = Locale(identifier: code)
    }
}
