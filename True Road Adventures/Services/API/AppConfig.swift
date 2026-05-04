import Foundation

struct AppConfig {
    let apiBaseURL: URL
    let paymentPublicKey: String?
    let pushUploadURL: URL?
    let googleMapsApiKey: String?
    let googlePlacesApiKey: String?
    let googleDirectionsApiKey: String?
    let customerBundleId: String?
    let driverBundleId: String?
    let useMockAPI: Bool

    static func load() -> AppConfig {
        let info = Bundle.main.infoDictionary ?? [:]

        // API_BASE_URL is injected via Driver.Debug.xcconfig / Driver.Release.xcconfig.
        // A missing or placeholder value here means the xcconfig is not applied to the target.
        let rawAPIURL = info["API_BASE_URL"] as? String ?? ""
        let isPlaceholder = rawAPIURL.isEmpty || rawAPIURL.contains("example.com")
        #if DEBUG
        if isPlaceholder {
            print("⚠️  AppConfig: API_BASE_URL not set. Check that the xcconfig is applied to the active target.")
        }
        #endif
        #if RIDER
        let fallbackAPIURL = "https://api.dev.trueroad.app/rider"
        #elseif DRIVER
        let fallbackAPIURL = "https://api.dev.trueroad.app/driver"
        #else
        let fallbackAPIURL = "https://api.dev.trueroad.app"
        #endif
        let apiBase = (!isPlaceholder ? URL(string: rawAPIURL) : nil)
            ?? URL(string: fallbackAPIURL)!

        let paymentKey = info["PAYMENT_PUBLIC_KEY"] as? String
        let pushURL = (info["PUSH_UPLOAD_URL"] as? String).flatMap(URL.init(string:))
        let mapsKey = info["GOOGLE_MAPS_API_KEY"] as? String
        let placesKey = info["GOOGLE_PLACES_API_KEY"] as? String ?? mapsKey
        let rawDirectionsKey = info["GOOGLE_DIRECTIONS_API_KEY"] as? String ?? ""
        // Use the dedicated Directions key if set; otherwise fall back to the Maps key
        // so existing projects work out of the box before a server key is configured.
        let resolvedDirectionsRaw = (rawDirectionsKey.isEmpty || rawDirectionsKey.hasPrefix("REPLACE_"))
            ? (mapsKey ?? "")
            : rawDirectionsKey
        let directionsKey: String? = resolvedDirectionsRaw.isEmpty ? nil : resolvedDirectionsRaw
        let customerBundleId = info["CUSTOMER_BUNDLE_ID"] as? String
        let driverBundleId = info["DRIVER_BUNDLE_ID"] as? String
        let useMockAPI = (info["USE_MOCK_API"] as? String)?.uppercased() == "YES"

        return AppConfig(
            apiBaseURL: apiBase,
            paymentPublicKey: paymentKey,
            pushUploadURL: pushURL,
            googleMapsApiKey: mapsKey,
            googlePlacesApiKey: placesKey,
            googleDirectionsApiKey: directionsKey,
            customerBundleId: customerBundleId,
            driverBundleId: driverBundleId,
            useMockAPI: useMockAPI
        )
    }
}
