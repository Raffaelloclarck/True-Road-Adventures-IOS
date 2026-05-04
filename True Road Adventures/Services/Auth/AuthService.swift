import Foundation
import Combine
import FirebaseAuth
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

@MainActor
final class AuthService: ObservableObject {
    struct State {
        var session: AuthSession?
        var user: User?
        var isLoading: Bool = false
        var error: String?
    }

    @Published private(set) var state = State()
    @Published private(set) var pendingDrivers: [User] = []
    var onSessionChanged: ((AuthSession?) -> Void)?

    private let repository: AuthRepository
    private let keychain = KeychainStore()
    private let accessKey = "auth.access"
    private let refreshKey = "auth.refresh"
    private let userIdKey = "auth.userId"
    private weak var languageManager: LanguageManager?
    private var pendingDriversTask: Task<Void, Never>?

    init(repository: AuthRepository, languageManager: LanguageManager? = nil) {
        self.repository = repository
        self.languageManager = languageManager
        restore()
        Task {
            await refreshUserFromStore()
            onSessionChanged?(state.session)
        }
    }

    func demoLogin() async throws {
        try await signIn(email: "demo@true-road.app", password: "password")
    }

    func signIn(email: String, password: String) async throws {
        await setLoading(true)
        do {
            let (session, user) = try await repository.signIn(email: email, password: password)
            save(session)
            setUser(user)
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
            throw error
        }
    }

    func register(email: String, password: String, displayName: String?, role: UserRole, referredBy: String? = nil) async throws {
        await setLoading(true)
        do {
            let (session, user) = try await repository.register(email: email, password: password, displayName: displayName, role: role, referredBy: referredBy)
            save(session)
            setUser(user)
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
            throw error
        }
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        await setLoading(true)
        do {
            let (session, user) = try await repository.signInWithGoogle(idToken: idToken, accessToken: accessToken)
            save(session)
            setUser(user)
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
            throw error
        }
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws {
        await setLoading(true)
        do {
            let (session, user) = try await repository.signInWithApple(idToken: idToken, rawNonce: rawNonce)
            save(session)
            setUser(user)
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
            throw error
        }
    }

    // MARK: - Phone auth (two-step, handled directly via Firebase)

    /// Step 1 – send verification SMS; returns a verificationID to pass to verifyPhoneCode.
    func sendVerificationCode(to phoneNumber: String) async throws -> String {
        await setLoading(true)
        do {
            let verificationID = try await PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil)
            await setLoading(false)
            return verificationID
        } catch {
            await setLoading(false, error: error.localizedDescription)
            throw error
        }
    }

    /// Step 2 – verify the OTP code from SMS.
    func verifyPhoneCode(_ code: String, verificationID: String) async throws {
        await setLoading(true)
        do {
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationID,
                verificationCode: code
            )
            let result = try await Auth.auth().signIn(with: credential)
            let idToken = try await result.user.getIDToken()
            let session = AuthSession(accessToken: idToken, refreshToken: nil, userId: result.user.uid)
            let user = User(
                id: result.user.uid,
                email: result.user.email,
                displayName: result.user.displayName,
                phoneNumber: result.user.phoneNumber,
                photoURL: result.user.photoURL,
                role: .customer
            )
            save(session)
            state.user = user
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
            throw error
        }
    }

    func sendPasswordReset(email: String) async {
        await setLoading(true)
        do {
            try await repository.sendPasswordReset(email: email)
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
        }
    }

    func updateProfile(displayName: String, phoneNumber: String) async {
        await setLoading(true)
        do {
            let user = try await repository.updateProfile(displayName: displayName, phoneNumber: phoneNumber)
            state.user = user
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
        }
    }

    func updatePhoto(url: URL) async {
        await setLoading(true)
        do {
            let user = try await repository.updatePhoto(url: url)
            state.user = user
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
        }
    }

    func uploadProfilePhoto(_ data: Data) async throws {
        #if canImport(FirebaseStorage)
        guard let userId = state.user?.id else { return }
        let ref = Storage.storage().reference().child("profile_photos/\(userId).jpg")
        var uploadError: Error?
        do {
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await ref.putDataAsync(data, metadata: metadata)
        } catch {
            uploadError = error
        }
        // Always attempt to fetch the download URL. If putDataAsync failed with
        // "already finalized" (a previous session completed the upload), the file
        // is already in Storage and downloadURL() will still succeed.
        // If the upload genuinely failed, downloadURL() also fails and we surface
        // the original upload error for better context.
        do {
            let url = try await ref.downloadURL()
            await updatePhoto(url: url)
        } catch {
            throw uploadError ?? error
        }
        #endif
    }

    func setDriverOnline(_ isOnline: Bool) async {
        await setLoading(true)
        do {
            let user = try await repository.setDriverOnline(isOnline)
            state.user = user
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
        }
    }

    func updateVehicleInfo(vehicleType: String?, licensePlate: String?) async {
        await setLoading(true)
        do {
            let user = try await repository.updateVehicleInfo(vehicle: VehicleInfo(vehicleType: vehicleType, licensePlate: licensePlate))
            state.user = user
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
        }
    }

    func updateSavedPlaces(home: String?, work: String?) async {
        await setLoading(true)
        do {
            let user = try await repository.updateSavedPlaces(SavedPlaces(home: home, work: work))
            state.user = user
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
        }
    }

    func addRecentAddress(_ address: String) async {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = state.user?.savedPlaces.recentAddresses ?? []
        current.removeAll { $0 == trimmed }
        current.insert(trimmed, at: 0)
        if current.count > 2 { current = Array(current.prefix(2)) }
        do {
            let user = try await repository.updateRecentAddresses(current)
            state.user = user
        } catch {
            // Recent address saving is best-effort — fail silently
        }
    }

    func updatePreferences(language: String?, marketingOptIn: Bool?) async {
        await setLoading(true)
        do {
            let user = try await repository.updatePreferences(UserPreferences(preferredLanguage: language, marketingOptIn: marketingOptIn))
            state.user = user
            if let lang = language {
                languageManager?.apply(lang)
            }
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
        }
    }

    func applyRideCredits(_ amount: Double) async {
        guard amount > 0 else { return }
        do {
            let user = try await repository.deductRideCredits(amount)
            state.user = user
        } catch {
            // Credits deduction is best-effort — the ride is already booked
        }
    }

    func completeOnboarding() async {
        do {
            let user = try await repository.completeOnboarding()
            state.user = user
        } catch {
            // Fail silently — the gate will stay open and the user can try again
        }
    }

    func deleteAccount() async {
        await setLoading(true)
        do {
            try await repository.deleteAccount()
            logout()
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
        }
    }

    func approveDriver(userId: String) async {
        do {
            try await repository.approveDriver(userId: userId)
        } catch {
            state.error = error.localizedDescription
        }
    }

    func rejectDriver(userId: String) async {
        do {
            try await repository.rejectDriver(userId: userId)
        } catch {
            state.error = error.localizedDescription
        }
    }

    func applyAsDriver() async {
        await setLoading(true)
        do {
            try await repository.applyAsDriver()
            await refreshUserFromStore()
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
        }
    }

    func startPendingDriversStream() {
        pendingDriversTask?.cancel()
        pendingDriversTask = Task { [weak self] in
            guard let self else { return }
            let stream = await repository.pendingDrivers()
            for await drivers in stream {
                await MainActor.run { self.pendingDrivers = drivers }
            }
        }
    }

    func logout() {
        pendingDriversTask?.cancel()
        pendingDriversTask = nil
        state.session = nil
        state.user = nil
        pendingDrivers = []
        keychain.remove(accessKey)
        keychain.remove(refreshKey)
        keychain.remove(userIdKey)
        onSessionChanged?(nil)
        Task {
            await repository.signOut()
        }
    }

    func setError(_ message: String?) {
        state.error = message
    }

    func refreshIfNeeded() async throws {
        guard state.session != nil else { return }
        let newSession = try await repository.refreshToken()
        save(newSession)
    }

    func getUserById(_ userId: String) async -> User? {
        await repository.getUserById(userId)
    }

    func fetchDriverRatings() async -> [Rating] {
        guard let userId = state.user?.id else { return [] }
        return (try? await repository.getDriverRatings(userId: userId)) ?? []
    }

    func fetchRatings(for driverId: String) async -> [Rating] {
        (try? await repository.getDriverRatings(userId: driverId)) ?? []
    }

    func currentToken() async -> String? {
        guard let firebaseUser = Auth.auth().currentUser else { return nil }
        return try? await firebaseUser.getIDToken()
    }

    func changePassword(currentPassword: String, newPassword: String) async {
        await setLoading(true)
        do {
            try await repository.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            await setLoading(false)
        } catch {
            await setLoading(false, error: error.localizedDescription)
        }
    }

    private func save(_ session: AuthSession) {
        state.session = session
        keychain.set(session.accessToken, for: accessKey)
        if let refresh = session.refreshToken {
            keychain.set(refresh, for: refreshKey)
        }
        keychain.set(session.userId, for: userIdKey)
        onSessionChanged?(session)
    }

    private func restore() {
        guard let access = keychain.get(accessKey),
              let userId = keychain.get(userIdKey) else { return }
        let refresh = keychain.get(refreshKey)
        state.session = AuthSession(accessToken: access, refreshToken: refresh, userId: userId)
    }

    private func refreshUserFromStore() async {
        if let user = await repository.currentUser() {
            await MainActor.run {
                state.user = user
                if let lang = user.preferences.preferredLanguage {
                    languageManager?.apply(lang)
                }
                if user.role == .admin {
                    startPendingDriversStream()
                }
            }
        }
    }

    private func setUser(_ user: User) {
        state.user = user
        if user.role == .admin {
            startPendingDriversStream()
        }
    }

    private func setLoading(_ loading: Bool, error: String? = nil) async {
        await MainActor.run {
            state.isLoading = loading
            state.error = error
        }
    }
}
