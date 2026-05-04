import SwiftUI

/// Applies the active locale from LanguageManager to the entire view hierarchy reactively.
/// SwiftUI automatically tracks the `locale` property access on the @Observable instance
/// and re-renders (and re-propagates the .environment key) whenever it changes.
struct LocaleApplierView<Content: View>: View {
    var languageManager: LanguageManager
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.locale, languageManager.locale)
    }
}
