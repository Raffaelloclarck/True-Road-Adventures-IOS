import Foundation

enum UserRole: String, CaseIterable, Codable, Sendable {
    case customer
    case driver
    case admin
}

// MARK: - Supporting value types
// Explicit nonisolated Codable implementations ensure these Sendable value
// types are usable from any actor context, even when the compiler infers
// global actor isolation on synthesised witnesses in Swift 6 strict mode.

struct VehicleInfo: Hashable, Sendable {
    var vehicleType: String?
    var licensePlate: String?

    nonisolated init(vehicleType: String? = nil, licensePlate: String? = nil) {
        self.vehicleType = vehicleType
        self.licensePlate = licensePlate
    }
}

extension VehicleInfo: Codable {
    private enum CodingKeys: String, CodingKey { case vehicleType, licensePlate }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vehicleType   = try c.decodeIfPresent(String.self, forKey: .vehicleType)
        licensePlate  = try c.decodeIfPresent(String.self, forKey: .licensePlate)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(vehicleType,  forKey: .vehicleType)
        try c.encodeIfPresent(licensePlate, forKey: .licensePlate)
    }
}

struct SavedPlaces: Hashable, Sendable {
    var home: String?
    var work: String?
    var recentAddresses: [String]

    nonisolated init(home: String? = nil, work: String? = nil, recentAddresses: [String] = []) {
        self.home = home
        self.work = work
        self.recentAddresses = recentAddresses
    }
}

extension SavedPlaces: Codable {
    private enum CodingKeys: String, CodingKey { case home, work, recentAddresses }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        home              = try c.decodeIfPresent(String.self,   forKey: .home)
        work              = try c.decodeIfPresent(String.self,   forKey: .work)
        recentAddresses   = (try c.decodeIfPresent([String].self, forKey: .recentAddresses)) ?? []
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(home,            forKey: .home)
        try c.encodeIfPresent(work,            forKey: .work)
        try c.encode(recentAddresses,          forKey: .recentAddresses)
    }
}

struct UserPreferences: Hashable, Sendable {
    var preferredLanguage: String?
    var marketingOptIn: Bool?

    nonisolated init(preferredLanguage: String? = nil, marketingOptIn: Bool? = nil) {
        self.preferredLanguage = preferredLanguage
        self.marketingOptIn    = marketingOptIn
    }
}

extension UserPreferences: Codable {
    private enum CodingKeys: String, CodingKey { case preferredLanguage, marketingOptIn }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preferredLanguage = try c.decodeIfPresent(String.self, forKey: .preferredLanguage)
        marketingOptIn    = try c.decodeIfPresent(Bool.self,   forKey: .marketingOptIn)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(preferredLanguage, forKey: .preferredLanguage)
        try c.encodeIfPresent(marketingOptIn,    forKey: .marketingOptIn)
    }
}

// MARK: - User

struct User: Identifiable, Hashable, Sendable {
    let id: String
    var email: String?
    var displayName: String?
    var phoneNumber: String?
    var photoURL: URL?
    var role: UserRole
    var isDriverOnline: Bool
    var vehicle: VehicleInfo
    var savedPlaces: SavedPlaces
    var preferences: UserPreferences
    var rating: Double?
    var completedRides: Int
    var hasCompletedOnboarding: Bool
    var isApproved: Bool
    var referralCode: String
    var rideCredits: Double
    var referredBy: String?

    nonisolated init(
        id: String,
        email: String? = nil,
        displayName: String? = nil,
        phoneNumber: String? = nil,
        photoURL: URL? = nil,
        role: UserRole,
        isDriverOnline: Bool = false,
        vehicle: VehicleInfo = VehicleInfo(),
        savedPlaces: SavedPlaces = SavedPlaces(),
        preferences: UserPreferences = UserPreferences(),
        rating: Double? = nil,
        completedRides: Int = 0,
        hasCompletedOnboarding: Bool = false,
        isApproved: Bool = true,
        referralCode: String = "",
        rideCredits: Double = 0,
        referredBy: String? = nil
    ) {
        self.id                     = id
        self.email                  = email
        self.displayName            = displayName
        self.phoneNumber            = phoneNumber
        self.photoURL               = photoURL
        self.role                   = role
        self.isDriverOnline         = isDriverOnline
        self.vehicle                = vehicle
        self.savedPlaces            = savedPlaces
        self.preferences            = preferences
        self.rating                 = rating
        self.completedRides         = completedRides
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.isApproved             = isApproved
        self.referralCode           = referralCode
        self.rideCredits            = rideCredits
        self.referredBy             = referredBy
    }
}

extension User: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, email, displayName, phoneNumber, photoURL
        case role, isDriverOnline, vehicle, savedPlaces, preferences
        case rating, completedRides, hasCompletedOnboarding, isApproved
        case referralCode, rideCredits, referredBy
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                     = try  c.decode(String.self,               forKey: .id)
        email                  = try  c.decodeIfPresent(String.self,       forKey: .email)
        displayName            = try  c.decodeIfPresent(String.self,       forKey: .displayName)
        phoneNumber            = try  c.decodeIfPresent(String.self,       forKey: .phoneNumber)
        photoURL               = try  c.decodeIfPresent(URL.self,          forKey: .photoURL)
        role                   = try  c.decode(UserRole.self,               forKey: .role)
        isDriverOnline         = (try c.decodeIfPresent(Bool.self,         forKey: .isDriverOnline))         ?? false
        vehicle                = (try c.decodeIfPresent(VehicleInfo.self,  forKey: .vehicle))                ?? VehicleInfo()
        savedPlaces            = (try c.decodeIfPresent(SavedPlaces.self,  forKey: .savedPlaces))            ?? SavedPlaces()
        preferences            = (try c.decodeIfPresent(UserPreferences.self, forKey: .preferences))        ?? UserPreferences()
        rating                 = try  c.decodeIfPresent(Double.self,       forKey: .rating)
        completedRides         = (try c.decodeIfPresent(Int.self,          forKey: .completedRides))         ?? 0
        hasCompletedOnboarding = (try c.decodeIfPresent(Bool.self,         forKey: .hasCompletedOnboarding)) ?? false
        isApproved             = (try c.decodeIfPresent(Bool.self,         forKey: .isApproved))             ?? true
        referralCode           = (try c.decodeIfPresent(String.self,       forKey: .referralCode))           ?? ""
        rideCredits            = (try c.decodeIfPresent(Double.self,       forKey: .rideCredits))            ?? 0
        referredBy             = try  c.decodeIfPresent(String.self,       forKey: .referredBy)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                            forKey: .id)
        try c.encodeIfPresent(email,                forKey: .email)
        try c.encodeIfPresent(displayName,          forKey: .displayName)
        try c.encodeIfPresent(phoneNumber,          forKey: .phoneNumber)
        try c.encodeIfPresent(photoURL,             forKey: .photoURL)
        try c.encode(role,                          forKey: .role)
        try c.encode(isDriverOnline,                forKey: .isDriverOnline)
        try c.encode(vehicle,                       forKey: .vehicle)
        try c.encode(savedPlaces,                   forKey: .savedPlaces)
        try c.encode(preferences,                   forKey: .preferences)
        try c.encodeIfPresent(rating,               forKey: .rating)
        try c.encode(completedRides,                forKey: .completedRides)
        try c.encode(hasCompletedOnboarding,        forKey: .hasCompletedOnboarding)
        try c.encode(isApproved,                    forKey: .isApproved)
        try c.encode(referralCode,                  forKey: .referralCode)
        try c.encode(rideCredits,                   forKey: .rideCredits)
        try c.encodeIfPresent(referredBy,           forKey: .referredBy)
    }
}
