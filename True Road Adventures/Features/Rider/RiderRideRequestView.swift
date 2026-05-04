import SwiftUI
import CoreLocation

struct RiderRideRequestView: View {
    var scheduledAt: Date?

    @EnvironmentObject private var rideService: RideService
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var authService: AuthService
    @Environment(LanguageManager.self) private var languageManager: LanguageManager
    @Environment(\.dismiss) private var dismiss

    @State private var pickup = ""
    @State private var destination = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedTier = 0
    @State private var isSchedulingEnabled: Bool
    @State private var scheduledDate: Date

    @State private var destinationSuggestions: [String] = []
    @State private var pickupSuggestions: [String] = []
    @State private var autocompleteTask: Task<Void, Never>?

    // Fare estimates per tier (nil = not yet fetched)
    @State private var fareEstimates: [Double?] = [nil, nil, nil]
    @State private var isFetchingEstimate = false
    @State private var estimateTask: Task<Void, Never>?
    @State private var cachedDestLatLng: LatLng?

    // Route preview on map
    @State private var previewRoutePoints: [Coordinate2D] = []
    @State private var previewPickupLatLng: LatLng?

    init(scheduledAt: Date?, prefillDestination: String? = nil) {
        self.scheduledAt = scheduledAt
        _isSchedulingEnabled = State(initialValue: scheduledAt != nil)
        _scheduledDate = State(initialValue: scheduledAt ?? Date().addingTimeInterval(3600))
        _destination = State(initialValue: prefillDestination ?? "")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer

            VStack(spacing: 0) {
                header
                Spacer()
                bottomPanel
            }
        }
        .ignoresSafeArea(.all, edges: [.top, .leading, .trailing])
        .navigationBarHidden(true)
        .onAppear {
            if pickup.isEmpty, let loc = locationService.lastLocation {
                reverseGeocode(loc)
            }
            if !destination.isEmpty {
                triggerFareEstimate()
            }
        }
        .alert(String(localized: "ride.request.error_title"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var mapLayer: some View {
        TRAGoogleMapView(
            pickup: previewPickupLatLng,
            destination: cachedDestLatLng,
            driverLocation: nil,
            customerLocation: nil,
            routePoints: previewRoutePoints,
            bearing: 0,
            speedKmh: 0,
            followDriver: false,
            showTraffic: false,
            onUserPanned: {}
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.gray900)
                    .frame(width: 40, height: 40)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.12), radius: 4)
            }
            .buttonStyle(.plain)

            Text("ride.request.title")
                .font(AppFont.titleMedium())
                .foregroundStyle(AppColors.gray900)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 60)
    }

    private var bottomPanel: some View {
        TRABottomSheet {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    addressInputs
                    schedulingRow
                    tierSelector
                    fareEstimateRow
                    TRAPrimaryButton(
                        title: "ride.request.button",
                        isLoading: isLoading,
                        isDisabled: !networkMonitor.isOnline || destination.isEmpty
                    ) {
                        submitRide()
                    }
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Address inputs

    private var recentAddresses: [String] {
        authService.state.user?.savedPlaces.recentAddresses ?? []
    }

    private var addressInputs: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Circle()
                    .fill(AppColors.boltGreen)
                    .frame(width: 10, height: 10)
                TRATextField(placeholder: "route.pickup_fallback", text: $pickup, icon: "location.fill")
            }
            if !pickupSuggestions.isEmpty {
                suggestionList(suggestions: pickupSuggestions) { selected in
                    pickup = selected
                    pickupSuggestions = []
                    triggerFareEstimate()
                }
            }

            HStack(spacing: 12) {
                Circle()
                    .fill(AppColors.errorRed)
                    .frame(width: 10, height: 10)
                TRATextField(placeholder: "route.destination_fallback", text: $destination, icon: "mappin")
            }
            if !destinationSuggestions.isEmpty {
                suggestionList(suggestions: destinationSuggestions) { selected in
                    destination = selected
                    destinationSuggestions = []
                    triggerFareEstimate()
                }
            } else if destination.isEmpty, !recentAddresses.isEmpty {
                recentAddressChips
            }
        }
        .onChange(of: destination) { _, newValue in
            fetchSuggestions(query: newValue, isPickup: false)
            if newValue.isEmpty {
                fareEstimates = [nil, nil, nil]
                previewRoutePoints = []
                cachedDestLatLng = nil
                estimateTask?.cancel()
            } else {
                triggerFareEstimate()
            }
        }
        .onChange(of: pickup) { _, newValue in
            fetchSuggestions(query: newValue, isPickup: true)
        }
    }

    private var recentAddressChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recentAddresses, id: \.self) { address in
                    Button {
                        destination = address
                        triggerFareEstimate()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.gray500)
                            Text(address)
                                .font(AppFont.labelSmall())
                                .foregroundStyle(AppColors.gray700)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.backgroundCard)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 22)
        }
    }

    // MARK: - Tier selector

    private var tierSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(RideTier.allCases.enumerated()), id: \.offset) { index, tier in
                    Button {
                        selectedTier = index
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tier.icon)
                                .font(.system(size: 22))
                                .foregroundStyle(selectedTier == index ? .white : AppColors.boltGreen)
                            Text(tier.displayName)
                                .font(AppFont.labelSmall())
                                .foregroundStyle(selectedTier == index ? .white : AppColors.gray700)
                            tierPriceLabel(index: index, isSelected: selectedTier == index)
                        }
                        .frame(width: 90, height: 80)
                        .background(selectedTier == index ? AppColors.boltGreen : AppColors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func tierPriceLabel(index: Int, isSelected: Bool) -> some View {
        if let fare = fareEstimates[safe: index] ?? nil {
            Text(String(format: "SRD %.0f", fare))
                .font(AppFont.labelSmall())
                .foregroundStyle(isSelected ? .white.opacity(0.9) : AppColors.boltGreen)
        } else if isFetchingEstimate {
            ProgressView()
                .scaleEffect(0.6)
                .tint(isSelected ? .white : AppColors.boltGreen)
        } else {
            Text("–")
                .font(AppFont.labelSmall())
                .foregroundStyle(isSelected ? .white.opacity(0.5) : AppColors.gray500)
        }
    }

    private var userCredits: Double { authService.state.user?.rideCredits ?? 0 }

    // MARK: - Fare estimate row

    private var fareEstimateRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(AppColors.boltGreen)
            VStack(alignment: .leading, spacing: 2) {
                if let fare = fareEstimates[safe: selectedTier] ?? nil {
                    if userCredits > 0 {
                        let (finalFare, applied) = FareCalculator.applyCredits(to: fare, credits: userCredits)
                        Text(String(format: String(localized: "ride.request.fare_estimate"), fare))
                            .font(AppFont.bodyMedium())
                            .foregroundStyle(AppColors.gray500)
                            .strikethrough()
                        Text(String(format: "SRD %.0f na korting", finalFare))
                            .font(AppFont.bodyMedium())
                            .foregroundStyle(AppColors.boltGreen)
                        Text(String(format: "− SRD %.2f tegoed verrekend", applied))
                            .font(AppFont.labelSmall())
                            .foregroundStyle(AppColors.boltGreen)
                    } else {
                        Text(String(format: String(localized: "ride.request.fare_estimate"), fare))
                            .font(AppFont.bodyMedium())
                            .foregroundStyle(AppColors.gray700)
                    }
                    Text("ride.request.wait_rate")
                        .font(AppFont.labelSmall())
                        .foregroundStyle(AppColors.gray500)
                } else if isFetchingEstimate {
                    Text("ride.request.calculating_fare")
                        .font(AppFont.bodyMedium())
                        .foregroundStyle(AppColors.gray500)
                } else if destination.isEmpty {
                    Text("ride.request.enter_destination")
                        .font(AppFont.bodyMedium())
                        .foregroundStyle(AppColors.gray500)
                } else {
                    Text("ride.request.estimate_unavailable")
                        .font(AppFont.bodyMedium())
                        .foregroundStyle(AppColors.gray500)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(AppColors.boltGreenLight)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r12))
    }

    // MARK: - Scheduling row

    private var schedulingRow: some View {
        VStack(spacing: 8) {
            Toggle(isOn: $isSchedulingEnabled.animation()) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundStyle(AppColors.boltGreen)
                    Text("ride.request.schedule_toggle")
                        .font(AppFont.bodyMedium())
                        .foregroundStyle(AppColors.gray700)
                }
            }
            .tint(AppColors.boltGreen)

            if isSchedulingEnabled {
                DatePicker(String(localized: "ride.request.date_time"), selection: $scheduledDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .tint(AppColors.boltGreen)
                    .font(AppFont.bodyMedium())
            }
        }
        .padding(12)
        .background(AppColors.boltGreenLight)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r12))
    }

    private func suggestionList(suggestions: [String], onSelect: @escaping (String) -> Void) -> some View {
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
        .padding(.leading, 22)
    }

    // MARK: - Fare estimate fetching

    private func triggerFareEstimate() {
        estimateTask?.cancel()
        guard !destination.isEmpty else {
            fareEstimates = [nil, nil, nil]
            return
        }
        estimateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, !destination.isEmpty else { return }

            isFetchingEstimate = true
            defer { isFetchingEstimate = false }

            let pickupLatLng: LatLng
            if let loc = locationService.lastLocation {
                pickupLatLng = LatLng(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            } else {
                pickupLatLng = LatLng(latitude: 5.8520, longitude: -55.2038)
            }

            guard let destLatLng = await geocodeAddress(destination) else { return }
            guard !Task.isCancelled else { return }

            cachedDestLatLng = destLatLng
            previewPickupLatLng = pickupLatLng
            let result = await rideService.fetchRoute(from: pickupLatLng, to: destLatLng)
            guard !Task.isCancelled else { return }

            previewRoutePoints = result.points

            let distanceKm: Double
            let durationSeconds: Int
            if result.distanceKm > 0 {
                distanceKm = result.distanceKm
                durationSeconds = result.totalDurationSeconds
            } else {
                let straight = haversineKm(pickupLatLng, destLatLng)
                distanceKm = straight * 1.3
                durationSeconds = Int(distanceKm / 30.0 * 3600)
            }

            fareEstimates = RideTier.allCases.map { tier in
                FareCalculator.realtimeFare(
                    distanceKm: distanceKm,
                    rideSeconds: durationSeconds,
                    waitSeconds: 0,
                    tier: tier
                )
            }
        }
    }

    // MARK: - Autocomplete

    private func fetchSuggestions(query: String, isPickup: Bool) {
        autocompleteTask?.cancel()
        if query.count < 2 {
            if isPickup { pickupSuggestions = [] } else { destinationSuggestions = [] }
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
                let descriptions = response.predictions.prefix(5).map { $0.description }
                if isPickup {
                    pickupSuggestions = Array(descriptions)
                } else {
                    destinationSuggestions = Array(descriptions)
                }
            } catch {
                // Suggestions are optional — fail silently
            }
        }
    }

    private struct PlacesAutocompleteResponse: Decodable {
        let predictions: [Prediction]
        struct Prediction: Decodable {
            let description: String
        }
    }

    // MARK: - Actions

    private func submitRide() {
        guard !destination.isEmpty else { return }
        isLoading = true
        Task {
            let customerId = authService.state.user?.id ?? ""
            let selectedRideTier = RideTier.allCases[selectedTier]

            let rawFare: Double
            if let fare = fareEstimates[safe: selectedTier] ?? nil {
                rawFare = fare
            } else {
                rawFare = FareCalculator.realtimeFare(
                    distanceKm: 0, rideSeconds: 0, waitSeconds: 0, tier: selectedRideTier
                )
            }
            let (estimatedFare, creditsToApply) = FareCalculator.applyCredits(to: rawFare, credits: userCredits)

            let pickupLatLng: LatLng
            if let loc = locationService.lastLocation {
                pickupLatLng = LatLng(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            } else {
                pickupLatLng = LatLng(latitude: 5.8520, longitude: -55.2038)
            }

            let destLatLng: LatLng
            if let cached = cachedDestLatLng {
                destLatLng = cached
            } else if let geocoded = await geocodeAddress(destination) {
                destLatLng = geocoded
            } else {
                destLatLng = LatLng(latitude: 5.8520, longitude: -55.2038)
            }

            do {
                try await rideService.requestRide(
                    customerId: customerId,
                    pickup: pickupLatLng,
                    destination: destLatLng,
                    pickupAddress: pickup.isEmpty ? String(localized: "ride.request.current_location") : pickup,
                    destinationAddress: destination,
                    scheduledAt: isSchedulingEnabled ? scheduledDate : nil,
                    tier: selectedRideTier,
                    estimatedFare: estimatedFare
                )
                if creditsToApply > 0 {
                    await authService.applyRideCredits(creditsToApply)
                }
                await authService.addRecentAddress(destination)
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch RideService.RideActionError.offline {
                await MainActor.run {
                    isLoading = false
                    errorMessage = String(localized: "ride.request.offline_error")
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func reverseGeocode(_ location: CLLocation) {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String,
              !apiKey.isEmpty else { return }
        Task {
            var components = URLComponents(string: "https://maps.googleapis.com/maps/api/geocode/json")!
            components.queryItems = [
                URLQueryItem(name: "latlng", value: "\(location.coordinate.latitude),\(location.coordinate.longitude)"),
                URLQueryItem(name: "language", value: languageManager.currentCode),
                URLQueryItem(name: "result_type", value: "street_address|route|locality"),
                URLQueryItem(name: "key", value: apiKey)
            ]
            guard let url = components.url else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(GeocodeResponse.self, from: data)
                if let address = response.results.first?.formatted_address {
                    await MainActor.run {
                        if pickup.isEmpty { pickup = address }
                    }
                }
            } catch {}
        }
    }

    private func haversineKm(_ from: LatLng, _ to: LatLng) -> Double {
        let earthRadiusKm = 6371.0
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
            sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusKm * c
    }

    private func geocodeAddress(_ address: String) async -> LatLng? {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String,
              !apiKey.isEmpty else { return nil }
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/geocode/json")!
        components.queryItems = [
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "language", value: languageManager.currentCode),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(GeocodeResponse.self, from: data)
            if let loc = response.results.first?.geometry.location {
                return LatLng(latitude: loc.lat, longitude: loc.lng)
            }
        } catch {}
        return nil
    }

    // MARK: - Geocoding DTOs

    private struct GeocodeResponse: Decodable {
        let results: [GeocodeResult]
    }

    private struct GeocodeResult: Decodable {
        let formatted_address: String
        let geometry: GeocodeGeometry
    }

    private struct GeocodeGeometry: Decodable {
        let location: GeocodeLoc
    }

    private struct GeocodeLoc: Decodable {
        let lat: Double
        let lng: Double
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    RiderRideRequestView(scheduledAt: nil)
        .environmentObject(
            RideService(
                repository: InMemoryRideRepository(),
                navigationManager: NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil))
            )
        )
        .environmentObject(NetworkMonitor.preview)
        .environmentObject(LocationService())
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
}
