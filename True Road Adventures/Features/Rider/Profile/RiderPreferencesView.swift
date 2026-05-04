import SwiftUI

struct RiderPreferencesView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var rideUpdates = true
    @State private var promotionalMessages = false
    @State private var languageCode = "nl"
    @State private var isSaving = false
    @State private var showLanguagePicker = false

    private let availableLanguageCodes = ["nl", "en", "de", "fr"]

    private func displayName(for code: String) -> LocalizedStringKey {
        switch code {
        case "en": return "preferences.lang.en"
        case "de": return "preferences.lang.de"
        case "fr": return "preferences.lang.fr"
        default:   return "preferences.lang.nl"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                preferenceSection(title: "preferences.section.notifications") {
                    preferenceToggle(
                        title: "preferences.notifications.rides.title",
                        subtitle: "preferences.notifications.rides.subtitle",
                        value: $rideUpdates,
                        onChange: { savePreferences() }
                    )
                    Divider().padding(.leading, 16)
                    preferenceToggle(
                        title: "preferences.notifications.promo.title",
                        subtitle: "preferences.notifications.promo.subtitle",
                        value: $promotionalMessages,
                        onChange: { savePreferences() }
                    )
                }

                preferenceSection(title: "preferences.section.app") {
                    Button { showLanguagePicker = true } label: {
                        HStack {
                            Text("preferences.language")
                                .font(AppFont.bodyMedium())
                                .foregroundStyle(AppColors.gray900)
                            Spacer()
                            Text(displayName(for: languageCode))
                                .font(AppFont.bodyMedium())
                                .foregroundStyle(AppColors.gray500)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.gray300)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 16)

                    HStack {
                        Text("preferences.currency")
                            .font(AppFont.bodyMedium())
                            .foregroundStyle(AppColors.gray900)
                        Spacer()
                        Text("SRD")
                            .font(AppFont.bodyMedium())
                            .foregroundStyle(AppColors.gray500)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                if isSaving {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("preferences.saving")
                            .font(AppFont.bodySmall())
                            .foregroundStyle(AppColors.gray500)
                    }
                }
            }
            .padding(16)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle(Text("preferences.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let prefs = authService.state.user?.preferences {
                promotionalMessages = prefs.marketingOptIn ?? false
                languageCode = prefs.preferredLanguage ?? "nl"
            }
        }
        .confirmationDialog(Text("preferences.language.picker.title"), isPresented: $showLanguagePicker, titleVisibility: .visible) {
            ForEach(availableLanguageCodes, id: \.self) { code in
                Button {
                    languageCode = code
                    savePreferences()
                } label: {
                    Text(displayName(for: code))
                }
            }
            Button(role: .cancel) {} label: { Text("preferences.language.cancel") }
        }
    }

    private func preferenceSection<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(AppFont.labelMedium()).foregroundStyle(AppColors.gray500)
                .padding(.horizontal, 4).padding(.bottom, 8)
            VStack(spacing: 0) { content() }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        }
    }

    private func preferenceToggle(title: LocalizedStringKey, subtitle: LocalizedStringKey, value: Binding<Bool>, onChange: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.bodyMedium()).foregroundStyle(AppColors.gray900)
                Text(subtitle).font(AppFont.bodySmall()).foregroundStyle(AppColors.gray500)
            }
            Spacer()
            Toggle("", isOn: value)
                .tint(AppColors.boltGreen)
                .labelsHidden()
                .onChange(of: value.wrappedValue) { _, _ in onChange() }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func savePreferences() {
        isSaving = true
        Task {
            await authService.updatePreferences(
                language: languageCode,
                marketingOptIn: promotionalMessages
            )
            await MainActor.run { isSaving = false }
        }
    }
}

#Preview { NavigationStack { RiderPreferencesView() }
    .environmentObject(AuthService(repository: InMemoryAuthRepository())) }
