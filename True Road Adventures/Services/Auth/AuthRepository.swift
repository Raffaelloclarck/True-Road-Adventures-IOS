import Foundation

protocol AuthRepository {
    func currentUser() async -> User?
    func getUserById(_ userId: String) async -> User?
    func signIn(email: String, password: String) async throws -> (AuthSession, User)
    func register(email: String, password: String, displayName: String?, role: UserRole, referredBy: String?) async throws -> (AuthSession, User)
    func signInWithGoogle(idToken: String, accessToken: String) async throws -> (AuthSession, User)
    func signInWithApple(idToken: String, rawNonce: String) async throws -> (AuthSession, User)
    func sendPasswordReset(email: String) async throws
    func changePassword(currentPassword: String, newPassword: String) async throws
    func refreshToken() async throws -> AuthSession
    func getDriverRatings(userId: String) async throws -> [Rating]
    func updateProfile(displayName: String, phoneNumber: String) async throws -> User
    func updatePhoto(url: URL) async throws -> User
    func setDriverOnline(_ isOnline: Bool) async throws -> User
    func updateVehicleInfo(vehicle: VehicleInfo) async throws -> User
    func updateSavedPlaces(_ saved: SavedPlaces) async throws -> User
    func updateRecentAddresses(_ addresses: [String]) async throws -> User
    func updatePreferences(_ preferences: UserPreferences) async throws -> User
    func completeOnboarding() async throws -> User
    func deductRideCredits(_ amount: Double) async throws -> User
    func deleteAccount() async throws
    func signOut() async

    func pendingDrivers() async -> AsyncStream<[User]>
    func approveDriver(userId: String) async throws
    func rejectDriver(userId: String) async throws
    func applyAsDriver() async throws
}

actor InMemoryAuthRepository: AuthRepository {
    private var users: [String: (user: User, password: String)] = [:]
    private var session: AuthSession?

    init(seedUsers: [User] = []) {
        for user in seedUsers {
            users[user.id] = (user, "password")
        }
    }

    func currentUser() async -> User? {
        guard let session else { return nil }
        return users[session.userId]?.user
    }

    func getUserById(_ userId: String) async -> User? {
        users[userId]?.user
    }

    func signIn(email: String, password: String) async throws -> (AuthSession, User) {
        guard let entry = users.values.first(where: { $0.user.email?.lowercased() == email.lowercased() }) else {
            throw NSError(domain: "Auth", code: 404, userInfo: [NSLocalizedDescriptionKey: "Account niet gevonden"])
        }
        guard entry.password == password else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Onjuist wachtwoord"])
        }
        let session = AuthSession(accessToken: UUID().uuidString, refreshToken: UUID().uuidString, userId: entry.user.id)
        self.session = session
        return (session, entry.user)
    }

    func register(email: String, password: String, displayName: String?, role: UserRole, referredBy: String? = nil) async throws -> (AuthSession, User) {
        if users.values.contains(where: { $0.user.email?.lowercased() == email.lowercased() }) {
            throw NSError(domain: "Auth", code: 409, userInfo: [NSLocalizedDescriptionKey: "Bestaat al"])
        }
        let newId = UUID().uuidString
        let code = "TRA-" + newId.prefix(6).uppercased()
        let user = User(id: newId, email: email, displayName: displayName, role: role, completedRides: 0, referralCode: code, referredBy: referredBy)
        users[user.id] = (user, password)
        let session = AuthSession(accessToken: UUID().uuidString, refreshToken: UUID().uuidString, userId: user.id)
        self.session = session
        return (session, user)
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> (AuthSession, User) {
        return try await signInOrCreate(email: idToken + "@google.local", displayName: "Google user", role: .customer)
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> (AuthSession, User) {
        return try await signInOrCreate(email: idToken + "@apple.local", displayName: "Apple user", role: .customer)
    }

    func sendPasswordReset(email: String) async throws {
        guard users.values.contains(where: { $0.user.email?.lowercased() == email.lowercased() }) else {
            throw NSError(domain: "Auth", code: 404, userInfo: [NSLocalizedDescriptionKey: "Onbekend e-mailadres"])
        }
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let session,
              var entry = users[session.userId] else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Niet ingelogd"])
        }
        guard entry.password == currentPassword else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Huidig wachtwoord onjuist"])
        }
        entry.password = newPassword
        users[session.userId] = entry
    }

    func getDriverRatings(userId: String) async throws -> [Rating] {
        return []
    }

    func refreshToken() async throws -> AuthSession {
        guard let session else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Niet ingelogd"])
        }
        let newSession = AuthSession(accessToken: UUID().uuidString, refreshToken: UUID().uuidString, userId: session.userId)
        self.session = newSession
        return newSession
    }

    func updateProfile(displayName: String, phoneNumber: String) async throws -> User {
        guard var user = try await requireUser() else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Niet ingelogd"])
        }
        user.displayName = displayName
        user.phoneNumber = phoneNumber
        users[user.id]?.user = user
        return user
    }

    func updatePhoto(url: URL) async throws -> User {
        guard var user = try await requireUser() else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Niet ingelogd"])
        }
        user.photoURL = url
        users[user.id]?.user = user
        return user
    }

    func setDriverOnline(_ isOnline: Bool) async throws -> User {
        guard var user = try await requireUser() else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Niet ingelogd"])
        }
        user.isDriverOnline = isOnline
        users[user.id]?.user = user
        return user
    }

    func updateVehicleInfo(vehicle: VehicleInfo) async throws -> User {
        guard var user = try await requireUser() else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Niet ingelogd"])
        }
        user.vehicle = vehicle
        users[user.id]?.user = user
        return user
    }

    func updateSavedPlaces(_ saved: SavedPlaces) async throws -> User {
        guard var user = try await requireUser() else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Niet ingelogd"])
        }
        user.savedPlaces = saved
        users[user.id]?.user = user
        return user
    }

    func updateRecentAddresses(_ addresses: [String]) async throws -> User {
        guard var user = try await requireUser() else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Niet ingelogd"])
        }
        user.savedPlaces.recentAddresses = addresses
        users[user.id]?.user = user
        return user
    }

    func updatePreferences(_ preferences: UserPreferences) async throws -> User {
        guard var user = try await requireUser() else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Niet ingelogd"])
        }
        user.preferences = preferences
        users[user.id]?.user = user
        return user
    }

    func completeOnboarding() async throws -> User {
        guard var user = try await requireUser() else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Niet ingelogd"])
        }
        user.hasCompletedOnboarding = true
        users[user.id]?.user = user
        return user
    }

    func deductRideCredits(_ amount: Double) async throws -> User {
        guard var user = try await requireUser() else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Niet ingelogd"])
        }
        user.rideCredits = max(0, user.rideCredits - amount)
        users[user.id]?.user = user
        return user
    }

    func deleteAccount() async throws {
        guard let user = try await requireUser() else { return }
        users[user.id] = nil
        session = nil
    }

    func signOut() async {
        session = nil
    }

    func pendingDrivers() async -> AsyncStream<[User]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [User].self)
        let pending = users.values
            .filter { $0.user.role == .driver && !$0.user.isApproved }
            .map(\.user)
            .sorted { $0.id < $1.id }
        continuation.yield(pending)
        continuation.finish()
        return stream
    }

    func approveDriver(userId: String) async throws {
        guard var entry = users[userId] else { return }
        entry.user.isApproved = true
        users[userId] = entry
    }

    func rejectDriver(userId: String) async throws {
        users[userId] = nil
    }

    func applyAsDriver() async throws {
        guard let userId = session?.userId, var entry = users[userId] else { return }
        entry.user.role = .driver
        entry.user.isApproved = false
        users[userId] = entry
    }

    private func signInOrCreate(email: String, displayName: String?, role: UserRole) async throws -> (AuthSession, User) {
        if let existing = users.values.first(where: { $0.user.email?.lowercased() == email.lowercased() }) {
            let session = AuthSession(accessToken: UUID().uuidString, refreshToken: UUID().uuidString, userId: existing.user.id)
            self.session = session
            return (session, existing.user)
        } else {
            return try await register(email: email, password: UUID().uuidString, displayName: displayName, role: role)
        }
    }

    private func requireUser() async throws -> User? {
        guard let session else { return nil }
        return users[session.userId]?.user
    }
}

/// API-backed implementation meant for production.
actor ApiAuthRepository: AuthRepository {
    private let client: ApiClient
    private var session: AuthSession?
    private var cachedUser: User?

    init(client: ApiClient) {
        self.client = client
    }

    func currentUser() async -> User? {
        if let cachedUser { return cachedUser }
        do {
            let user: User = try await request(.init(path: "/auth/me"))
            cachedUser = user
            return user
        } catch {
            return nil
        }
    }

    func getUserById(_ userId: String) async -> User? {
        try? await request(.init(path: "/users/\(userId)"))
    }

    func signIn(email: String, password: String) async throws -> (AuthSession, User) {
        let response: AuthEnvelope = try await request(
            .init(path: "/auth/login", method: "POST", body: ["email": email, "password": password]),
            auth: false
        )
        setSession(response.session, user: response.user)
        return (response.session, response.user)
    }

    func register(email: String, password: String, displayName: String?, role: UserRole, referredBy: String? = nil) async throws -> (AuthSession, User) {
        struct RegisterBody: Encodable {
            let email: String
            let password: String
            let displayName: String?
            let role: String
            let referredBy: String?
        }
        let body = RegisterBody(
            email: email,
            password: password,
            displayName: displayName,
            role: role.rawValue,
            referredBy: referredBy
        )
        let response: AuthEnvelope = try await request(
            .init(path: "/auth/register", method: "POST", body: body),
            auth: false
        )
        setSession(response.session, user: response.user)
        return (response.session, response.user)
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> (AuthSession, User) {
        let response: AuthEnvelope = try await request(
            .init(path: "/auth/google", method: "POST", body: ["idToken": idToken, "accessToken": accessToken]),
            auth: false
        )
        setSession(response.session, user: response.user)
        return (response.session, response.user)
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> (AuthSession, User) {
        let response: AuthEnvelope = try await request(
            .init(path: "/auth/apple", method: "POST", body: ["idToken": idToken]),
            auth: false
        )
        setSession(response.session, user: response.user)
        return (response.session, response.user)
    }

    func sendPasswordReset(email: String) async throws {
        _ = try await request(EmptyResponse.self, .init(path: "/auth/reset", method: "POST", body: ["email": email]), auth: false)
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        _ = try await request(EmptyResponse.self, .init(
            path: "/auth/password",
            method: "PATCH",
            body: ["currentPassword": currentPassword, "newPassword": newPassword]
        ))
    }

    func getDriverRatings(userId: String) async throws -> [Rating] {
        struct RatingsEnvelope: Decodable { let ratings: [Rating] }
        let envelope: RatingsEnvelope = try await request(.init(path: "/driver/\(userId)/ratings"))
        return envelope.ratings
    }

    func refreshToken() async throws -> AuthSession {
        struct RefreshBody: Encodable { let refreshToken: String }
        guard let rt = session?.refreshToken else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Geen refresh token beschikbaar"])
        }
        let newSession: AuthSession = try await request(
            .init(path: "/auth/refresh", method: "POST", body: RefreshBody(refreshToken: rt)),
            auth: false
        )
        session = newSession
        return newSession
    }

    func updateProfile(displayName: String, phoneNumber: String) async throws -> User {
        let user: User = try await request(
            .init(path: "/profile", method: "PATCH", body: ["displayName": displayName, "phoneNumber": phoneNumber])
        )
        cachedUser = user
        return user
    }

    func updatePhoto(url: URL) async throws -> User {
        let user: User = try await request(
            .init(path: "/profile/photo", method: "PATCH", body: ["photoUrl": url.absoluteString])
        )
        cachedUser = user
        return user
    }

    func setDriverOnline(_ isOnline: Bool) async throws -> User {
        let user: User = try await request(
            .init(path: "/driver/availability", method: "PATCH", body: ["online": isOnline])
        )
        cachedUser = user
        return user
    }

    func updateVehicleInfo(vehicle: VehicleInfo) async throws -> User {
        let user: User = try await request(
            .init(path: "/driver/vehicle", method: "PATCH", body: vehicle)
        )
        cachedUser = user
        return user
    }

    func updateSavedPlaces(_ saved: SavedPlaces) async throws -> User {
        let user: User = try await request(
            .init(path: "/profile/saved-places", method: "PATCH", body: saved)
        )
        cachedUser = user
        return user
    }

    func updateRecentAddresses(_ addresses: [String]) async throws -> User {
        struct Body: Encodable { let recentAddresses: [String] }
        let user: User = try await request(
            .init(path: "/profile/recent-addresses", method: "PATCH", body: Body(recentAddresses: addresses))
        )
        cachedUser = user
        return user
    }

    func updatePreferences(_ preferences: UserPreferences) async throws -> User {
        let user: User = try await request(
            .init(path: "/profile/preferences", method: "PATCH", body: preferences)
        )
        cachedUser = user
        return user
    }

    func completeOnboarding() async throws -> User {
        let user: User = try await request(
            .init(path: "/profile", method: "PATCH", body: ["hasCompletedOnboarding": true])
        )
        cachedUser = user
        return user
    }

    func deductRideCredits(_ amount: Double) async throws -> User {
        let user: User = try await request(
            .init(path: "/profile/credits/deduct", method: "POST", body: ["amount": amount])
        )
        cachedUser = user
        return user
    }

    func deleteAccount() async throws {
        _ = try await request(EmptyResponse.self, .init(path: "/auth", method: "DELETE"))
        session = nil
        cachedUser = nil
    }

    func pendingDrivers() async -> AsyncStream<[User]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [User].self)
        let task = Task { [weak self] in
            var delay: UInt64 = 5_000_000_000
            while !Task.isCancelled {
                guard let self else { break }
                do {
                    let users: [User] = try await request(.init(path: "/admin/drivers/pending"))
                    continuation.yield(users)
                    delay = 5_000_000_000
                } catch {
                    continuation.yield([])
                    delay = min(delay * 2, 30_000_000_000)
                }
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
        return stream
    }

    func approveDriver(userId: String) async throws {
        _ = try await request(EmptyResponse.self, .init(path: "/admin/drivers/\(userId)/approve", method: "POST"))
    }

    func rejectDriver(userId: String) async throws {
        _ = try await request(EmptyResponse.self, .init(path: "/admin/drivers/\(userId)", method: "DELETE"))
    }

    func applyAsDriver() async throws {
        _ = try await request(EmptyResponse.self, .init(path: "/auth/apply-driver", method: "POST"))
    }

    func signOut() async {
        _ = try? await request(EmptyResponse.self, .init(path: "/auth/logout", method: "POST"))
        session = nil
        cachedUser = nil
    }

    // MARK: - Helpers

    private func setSession(_ session: AuthSession, user: User) {
        self.session = session
        self.cachedUser = user
    }

    private func request<T: Decodable>(_ request: ApiRequest, auth: Bool = true) async throws -> T {
        try await self.request(T.self, request, auth: auth)
    }

    private func request<T: Decodable>(_ type: T.Type, _ request: ApiRequest, auth: Bool = true) async throws -> T {
        let token = auth ? session?.accessToken : nil
        return try await client.send(request, decode: type, token: token)
    }

    private struct AuthEnvelope: Decodable {
        let session: AuthSession
        let user: User
    }

    private struct EmptyResponse: Decodable { }
}
