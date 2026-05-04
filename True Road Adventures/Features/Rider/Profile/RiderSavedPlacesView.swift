import SwiftUI
import CoreLocation

struct RiderSavedPlacesView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var locationService: LocationService
    @Environment(LanguageManager.self) private var languageManager: LanguageManager
    @Environment(\.dismiss) private var dismiss

    @State private var homeAddress: String = ""
    @State private var workAddress: String = ""
    @State private var isSaving = false
    @State private var editingField: EditField? = nil
    @State private var editText = ""
    @State private var suggestions: [String] = []
    @State private var autocompleteTask: Task<Void, Never>? = nil

    enum EditField: Identifiable {
        case home, work
        var id: Self { self }
        var title: String { self == .home ? "Thuisadres" : "Werkadres" }
        var icon: String { self == .home ? "house.fill" : "briefcase.fill" }
        var placeholder: LocalizedStringKey { self == .home ? "Voeg thuisadres toe" : "Voeg werkadres toe" }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                placeRow(
                    icon: "house.fill",
                    title: "Thuis",
                    address: homeAddress.isEmpty ? "Voeg je thuisadres toe" : homeAddress,
                    isEmpty: homeAddress.isEmpty,
                    onTap: { startEditing(.home) }
                )
                placeRow(
                    icon: "briefcase.fill",
                    title: "Werk",
                    address: workAddress.isEmpty ? "Voeg je werkadres toe" : workAddress,
                    isEmpty: workAddress.isEmpty,
                    onTap: { startEditing(.work) }
                )

                TRASecondaryButton(title: "Locatie toevoegen", icon: "plus") {
                    startEditing(homeAddress.isEmpty ? .home : .work)
                }
            }
            .padding(16)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle("Opgeslagen plaatsen")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            homeAddress = authService.state.user?.savedPlaces.home ?? ""
            workAddress = authService.state.user?.savedPlaces.work ?? ""
        }
        .sheet(item: $editingField) { field in
            editSheet(for: field)
        }
        .onChange(of: editingField) { _, newValue in
            if newValue == nil {
                suggestions = []
                autocompleteTask?.cancel()
            }
        }
    }

    private func placeRow(icon: String, title: String, address: String, isEmpty: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.boltGreen.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.boltGreen)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.titleSmall())
                        .foregroundStyle(AppColors.gray900)
                    Text(address)
                        .font(AppFont.bodySmall())
                        .foregroundStyle(isEmpty ? AppColors.gray500 : AppColors.gray700)
                }
                Spacer()
                Image(systemName: isEmpty ? "plus.circle" : "pencil")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.boltGreen)
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        }
        .buttonStyle(.plain)
    }

    private func editSheet(for field: EditField) -> some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppColors.boltGreenLight)
                            .frame(width: 48, height: 48)
                        Image(systemName: field.icon)
                            .foregroundStyle(AppColors.boltGreen)
                    }
                    Text(field.title)
                        .font(AppFont.titleMedium())
                        .foregroundStyle(AppColors.gray900)
                    Spacer()
                }

                TRATextField(placeholder: field.placeholder, text: $editText, icon: "mappin")
                    .onChange(of: editText) { _, newValue in
                        fetchSuggestions(query: newValue)
                    }

                if !suggestions.isEmpty {
                    suggestionList { selected in
                        editText = selected
                        suggestions = []
                    }
                }

                TRAPrimaryButton(title: "Opslaan", isLoading: isSaving) {
                    saveField(field)
                }

                if !editText.isEmpty {
                    TRASecondaryButton(title: "Verwijderen", icon: "trash") {
                        editText = ""
                        saveField(field)
                    }
                }

                Spacer()
            }
            .padding(24)
            .background(AppColors.backgroundLight)
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuleer") { editingField = nil }
                        .foregroundStyle(AppColors.gray700)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func startEditing(_ field: EditField) {
        editText = field == .home ? homeAddress : workAddress
        editingField = field
    }

    private func fetchSuggestions(query: String) {
        autocompleteTask?.cancel()
        if query.count < 2 {
            suggestions = []
            return
        }
        autocompleteTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_PLACES_API_KEY") as? String,
                  !apiKey.isEmpty else { return }

            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "input", value: query),
                URLQueryItem(name: "key", value: apiKey),
                URLQueryItem(name: "language", value: languageManager.currentCode),
                URLQueryItem(name: "types", value: "geocode")
            ]

            if let loc = locationService.lastLocation {
                queryItems.append(URLQueryItem(name: "location", value: "\(loc.coordinate.latitude),\(loc.coordinate.longitude)"))
                queryItems.append(URLQueryItem(name: "radius", value: "50000"))
            }

            var components = URLComponents(string: "https://maps.googleapis.com/maps/api/place/autocomplete/json")!
            components.queryItems = queryItems

            guard let url = components.url else { return }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled else { return }
                let response = try JSONDecoder().decode(PlacesAutocompleteResponse.self, from: data)
                suggestions = Array(response.predictions.prefix(5).map { $0.description })
            } catch {
                // Suggestions are optional — fail silently
            }
        }
    }

    private func suggestionList(onSelect: @escaping (String) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.gray500)
                            .frame(width: 18)
                        Text(suggestion)
                            .font(AppFont.bodyMedium())
                            .foregroundStyle(AppColors.gray900)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                if suggestion != suggestions.last {
                    Divider().padding(.leading, 40)
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r12))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
    }

    private struct PlacesAutocompleteResponse: Decodable {
        let predictions: [Prediction]
        struct Prediction: Decodable {
            let description: String
        }
    }

    private func saveField(_ field: EditField) {
        switch field {
        case .home: homeAddress = editText
        case .work: workAddress = editText
        }
        isSaving = true
        Task {
            await authService.updateSavedPlaces(
                home: homeAddress.isEmpty ? nil : homeAddress,
                work: workAddress.isEmpty ? nil : workAddress
            )
            await MainActor.run {
                isSaving = false
                editingField = nil
            }
        }
    }
}

#Preview { NavigationStack { RiderSavedPlacesView() }
    .environmentObject(AuthService(repository: InMemoryAuthRepository())) }
