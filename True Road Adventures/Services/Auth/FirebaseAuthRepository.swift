import Foundation
import FirebaseAuth
import GoogleSignIn
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
actor FirebaseAuthRepository: AuthRepository {
    private let defaultRole: UserRole
    private var cachedUser: User?

    init(appMode: AppMode) {
        self.defaultRole = appMode == .driver ? .driver : .customer
    }

    // MARK: - Read

    func getUserById(_ userId: String) async -> User? {
        #if canImport(FirebaseFirestore)
        guard let data = try? await Firestore.firestore()
            .collection("users").document(userId).getDocument().data() else {
            return nil
        }
        return Self.makeUserFromFirestore(
            id: userId,
            data: data,
            defaultRoleWhenUnknown: defaultRole
        )
        #else
        return nil
        #endif
    }

    func currentUser() async -> User? {
        guard let firebaseUser = Auth.auth().currentUser else { return nil }
        if let cached = cachedUser { return cached }
        if let fetched = await fetchUserFromFirestore(firebaseUser) {
            cachedUser = fetched
            return fetched
        }
        return await mapUser(firebaseUser)
    }

    func refreshCurrentUser() async -> User? {
        guard let firebaseUser = Auth.auth().currentUser else { return nil }
        cachedUser = nil
        // Use a generous 30-second timeout for background refresh
        let fetched = await fetchUserFromFirestoreWithTimeout(firebaseUser, timeout: 30)
        if let fetched {
            cachedUser = fetched
            return fetched
        }
        return await mapUser(firebaseUser)
    }

    // MARK: - Firestore helpers

    private func fetchUserFromFirestore(_ firebaseUser: FirebaseAuth.User) async -> User? {
        #if canImport(FirebaseFirestore)
        guard let data = try? await Firestore.firestore()
            .collection("users").document(firebaseUser.uid).getDocument().data() else {
            return nil
        }
        let roleStr = (data["role"] as? String ?? "")
        if roleStr.isEmpty {
            print("[FirebaseAuthRepository] Warning: user \(firebaseUser.uid) has no 'role' field in Firestore — defaulting to \(defaultRole). Set role: \"DRIVER\" in the users collection for driver accounts.")
        }
        return Self.makeUserFromFirestore(
            id: firebaseUser.uid,
            data: data,
            defaultRoleWhenUnknown: defaultRole,
            emailFallback: firebaseUser.email,
            displayNameFallback: firebaseUser.displayName,
            phoneFallback: firebaseUser.phoneNumber,
            photoFallback: firebaseUser.photoURL
        )
        #else
        return nil
        #endif
    }

    private func upsertFirestoreUser(_ firebaseUser: FirebaseAuth.User, role: UserRole, referredBy: String? = nil) async {
        #if canImport(FirebaseFirestore)
        let ref = Firestore.firestore().collection("users").document(firebaseUser.uid)
        let existing = try? await ref.getDocument()
        if existing?.exists == false {
            let generatedCode = "TRA-" + firebaseUser.uid.prefix(6).uppercased()
            var data: [String: Any] = [
                "email": firebaseUser.email ?? "",
                "displayName": firebaseUser.displayName ?? "",
                "role": role == .admin ? "ADMIN" : "",
                "isDriver": role == .driver,
                "isCustomer": role == .customer,
                "isOnline": false,
                "isApproved": role != .driver,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "preferredLanguage": "nl",
                "marketingOptIn": true,
                "referralCode": generatedCode,
                "rideCredits": 0.0,
            ]
            if let code = referredBy, !code.trimmingCharacters(in: .whitespaces).isEmpty {
                data["referredBy"] = code.trimmingCharacters(in: .whitespaces).uppercased()
            }
            try? await ref.setData(data)
        } else {
            let existingData = existing?.data() ?? [:]
            // Only sync profile fields — never overwrite role or revoke existing permissions
            var updateData: [String: Any] = [
                "email": firebaseUser.email ?? "",
                "displayName": firebaseUser.displayName ?? "",
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            // Backfill isCustomer/isDriver for legacy users who registered before these fields existed
            if existingData["isCustomer"] == nil && existingData["isDriver"] == nil {
                let legacyRole = (existingData["role"] as? String ?? "").uppercased()
                updateData["isDriver"] = legacyRole == "DRIVER"
                updateData["isCustomer"] = legacyRole == "CUSTOMER"
            }
            // Customer app: mark this account as having a customer role
            if defaultRole == .customer {
                updateData["isCustomer"] = true
            }
            // Driver app: only set isDriver if the account already has driver status
            // (new driver registrations go through applyAsDriver)
            if defaultRole == .driver {
                let alreadyDriver = (existingData["isDriver"] as? Bool ?? false)
                    || (existingData["role"] as? String ?? "").uppercased() == "DRIVER"
                if alreadyDriver {
                    updateData["isDriver"] = true
                }
            }
            // Backfill referralCode for legacy users who registered before this field existed
            let existingCode = existingData["referralCode"] as? String ?? ""
            if existingCode.isEmpty {
                updateData["referralCode"] = "TRA-" + firebaseUser.uid.prefix(6).uppercased()
            }
            try? await ref.updateData(updateData)
        }
        #endif
    }

    // MARK: - Email / password

    func signIn(email: String, password: String) async throws -> (AuthSession, User) {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return try await buildResult(result.user)
    }

    func register(email: String, password: String, displayName: String?, role: UserRole, referredBy: String? = nil) async throws -> (AuthSession, User) {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        if let name = displayName {
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = name
            try await changeRequest.commitChanges()
        }
        return try await buildResult(result.user, role: role, referredBy: referredBy)
    }

    // MARK: - Social sign-in

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> (AuthSession, User) {
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        let result = try await Auth.auth().signIn(with: credential)
        return try await buildResult(result.user)
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> (AuthSession, User) {
        let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: rawNonce, fullName: nil)
        let result = try await Auth.auth().signIn(with: credential)
        return try await buildResult(result.user)
    }

    // MARK: - Password reset

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let firebaseUser = Auth.auth().currentUser,
              let email = firebaseUser.email else {
            throw AuthError.notAuthenticated
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        try await firebaseUser.reauthenticate(with: credential)
        try await firebaseUser.updatePassword(to: newPassword)
    }

    func getDriverRatings(userId: String) async throws -> [Rating] {
        #if canImport(FirebaseFirestore)
        let snapshot = try await Firestore.firestore()
            .collection("ratings")
            .whereField("toUserId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments()
        return snapshot.documents.compactMap { doc -> Rating? in
            let data = doc.data()
            guard let rideId = data["rideId"] as? String,
                  let fromUserId = data["fromUserId"] as? String,
                  let score = data["score"] as? Int else { return nil }
            let comment = (data["comment"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let createdAtMs = (data["createdAt"] as? NSNumber)?.doubleValue ?? 0
            let createdAt = Date(timeIntervalSince1970: createdAtMs / 1000)
            return Rating(id: doc.documentID, rideId: rideId, fromUserId: fromUserId,
                          toUserId: userId, score: score, comment: comment, createdAt: createdAt)
        }
        #else
        return []
        #endif
    }

    func refreshToken() async throws -> AuthSession {
        guard let firebaseUser = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }
        let idToken = try await firebaseUser.getIDToken(forcingRefresh: true)
        return AuthSession(accessToken: idToken, refreshToken: nil, userId: firebaseUser.uid)
    }

    // MARK: - Profile operations

    func updateProfile(displayName: String, phoneNumber: String) async throws -> User {
        guard let firebaseUser = Auth.auth().currentUser,
              var user = try await cachedOrCurrentUser() else {
            throw AuthError.notAuthenticated
        }
        let changeRequest = firebaseUser.createProfileChangeRequest()
        changeRequest.displayName = displayName
        try await changeRequest.commitChanges()
        user.displayName = displayName
        user.phoneNumber = phoneNumber
        #if canImport(FirebaseFirestore)
        var fields: [String: Any] = ["displayName": displayName, "updatedAt": FieldValue.serverTimestamp()]
        if !phoneNumber.isEmpty { fields["phoneNumber"] = phoneNumber }
        try? await Firestore.firestore().collection("users").document(firebaseUser.uid)
            .updateData(fields)
        #endif
        cachedUser = user
        return user
    }

    func updatePhoto(url: URL) async throws -> User {
        guard let firebaseUser = Auth.auth().currentUser,
              var user = try await cachedOrCurrentUser() else {
            throw AuthError.notAuthenticated
        }
        let changeRequest = firebaseUser.createProfileChangeRequest()
        changeRequest.photoURL = url
        try await changeRequest.commitChanges()
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore().collection("users").document(firebaseUser.uid)
            .updateData(["photoURL": url.absoluteString])
        #endif
        user.photoURL = url
        cachedUser = user
        return user
    }

    func setDriverOnline(_ isOnline: Bool) async throws -> User {
        guard let firebaseUser = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore().collection("users").document(firebaseUser.uid)
            .updateData(["isOnline": isOnline])
        #endif
        guard var user = try await cachedOrCurrentUser() else {
            throw AuthError.notAuthenticated
        }
        user.isDriverOnline = isOnline
        cachedUser = user
        return user
    }

    func saveAvailability(slots: [String: AvailabilitySlot], enabled: Bool) async throws -> User {
        guard let firebaseUser = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }
        #if canImport(FirebaseFirestore)
        let slotsData: [String: [String: Any]] = slots.mapValues { slot in
            ["isEnabled": slot.isEnabled, "startTime": slot.startTime, "endTime": slot.endTime]
        }
        try await Firestore.firestore().collection("users").document(firebaseUser.uid)
            .updateData(["availability": slotsData, "availabilityEnabled": enabled])
        #endif
        guard var user = try await cachedOrCurrentUser() else {
            throw AuthError.notAuthenticated
        }
        user.weeklyAvailability  = slots
        user.availabilityEnabled = enabled
        cachedUser = user
        return user
    }

    func updateVehicleInfo(vehicle: VehicleInfo) async throws -> User {
        guard let firebaseUser = Auth.auth().currentUser,
              var user = try await cachedOrCurrentUser() else {
            throw AuthError.notAuthenticated
        }
        #if canImport(FirebaseFirestore)
        var fields: [String: Any] = [:]
        if let type = vehicle.vehicleType  { fields["vehicleType"]  = type }
        if let plate = vehicle.licensePlate { fields["licensePlate"] = plate }
        if !fields.isEmpty {
            try? await Firestore.firestore().collection("users").document(firebaseUser.uid)
                .updateData(fields)
        }
        #endif
        user.vehicle = vehicle
        cachedUser = user
        return user
    }

    func updateSavedPlaces(_ saved: SavedPlaces) async throws -> User {
        guard let firebaseUser = Auth.auth().currentUser,
              var user = try await cachedOrCurrentUser() else {
            throw AuthError.notAuthenticated
        }
        #if canImport(FirebaseFirestore)
        var fields: [String: Any] = [:]
        if let home = saved.home { fields["homeAddress"] = home }
        if let work = saved.work { fields["workAddress"]  = work }
        if !fields.isEmpty {
            try? await Firestore.firestore().collection("users").document(firebaseUser.uid)
                .updateData(fields)
        }
        #endif
        user.savedPlaces = saved
        cachedUser = user
        return user
    }

    func updateRecentAddresses(_ addresses: [String]) async throws -> User {
        guard let firebaseUser = Auth.auth().currentUser,
              var user = try await cachedOrCurrentUser() else {
            throw AuthError.notAuthenticated
        }
        #if canImport(FirebaseFirestore)
        try? await Firestore.firestore().collection("users").document(firebaseUser.uid)
            .updateData(["recentAddresses": addresses])
        #endif
        user.savedPlaces.recentAddresses = addresses
        cachedUser = user
        return user
    }

    func updatePreferences(_ preferences: UserPreferences) async throws -> User {
        guard let firebaseUser = Auth.auth().currentUser,
              var user = try await cachedOrCurrentUser() else {
            throw AuthError.notAuthenticated
        }
        #if canImport(FirebaseFirestore)
        var fields: [String: Any] = [:]
        if let lang = preferences.preferredLanguage { fields["preferredLanguage"] = lang }
        if let opt  = preferences.marketingOptIn    { fields["marketingOptIn"]    = opt }
        if !fields.isEmpty {
            try? await Firestore.firestore().collection("users").document(firebaseUser.uid)
                .updateData(fields)
        }
        #endif
        user.preferences = preferences
        cachedUser = user
        return user
    }

    func completeOnboarding() async throws -> User {
        guard let firebaseUser = Auth.auth().currentUser,
              var user = try await cachedOrCurrentUser() else {
            throw AuthError.notAuthenticated
        }
        #if canImport(FirebaseFirestore)
        try? await Firestore.firestore().collection("users").document(firebaseUser.uid)
            .updateData(["hasCompletedOnboarding": true])
        #endif
        user.hasCompletedOnboarding = true
        cachedUser = user
        return user
    }

    func deductRideCredits(_ amount: Double) async throws -> User {
        guard let firebaseUser = Auth.auth().currentUser,
              var user = try await cachedOrCurrentUser() else {
            throw AuthError.notAuthenticated
        }
        let deduction = min(max(amount, 0), user.rideCredits)
        guard deduction > 0 else { return user }
        #if canImport(FirebaseFirestore)
        try? await Firestore.firestore().collection("users").document(firebaseUser.uid)
            .updateData(["rideCredits": max(0, user.rideCredits - deduction)])
        #endif
        user.rideCredits = max(0, user.rideCredits - deduction)
        cachedUser = user
        return user
    }

    func deleteAccount() async throws {
        guard let firebaseUser = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }
        try await firebaseUser.delete()
        cachedUser = nil
    }

    func pendingDrivers() async -> AsyncStream<[User]> {
        #if canImport(FirebaseFirestore)
        let (stream, continuation) = AsyncStream.makeStream(of: [User].self)
        let query = Firestore.firestore().collection("users")
            .whereField("role", isEqualTo: "DRIVER")
            .whereField("isApproved", isEqualTo: false)
        let listener = query.addSnapshotListener { snapshot, _ in
            let users: [User] = snapshot?.documents.compactMap { doc -> User? in
                let data = doc.data()
                let photoURL = (data["photoURL"] as? String).flatMap { URL(string: $0) }
                return User(
                    id: doc.documentID,
                    email: data["email"] as? String,
                    displayName: data["displayName"] as? String,
                    phoneNumber: data["phoneNumber"] as? String,
                    photoURL: photoURL,
                    role: .driver,
                    isApproved: false
                )
            } ?? []
            continuation.yield(users)
        }
        continuation.onTermination = { @Sendable _ in listener.remove() }
        return stream
        #else
        return AsyncStream { $0.finish() }
        #endif
    }

    func approvedDriversDirectory() async -> AsyncStream<[User]> {
        #if canImport(FirebaseFirestore)
        let (stream, continuation) = AsyncStream.makeStream(of: [User].self)
        let query = Firestore.firestore().collection("users")
            .whereField("role", isEqualTo: "DRIVER")
            .whereField("isApproved", isEqualTo: true)
        let listener = query.addSnapshotListener { snapshot, _ in
            var users: [User] = snapshot?.documents.map { doc in
                Self.makeUserFromFirestore(
                    id: doc.documentID,
                    data: doc.data(),
                    defaultRoleWhenUnknown: .driver
                )
            } ?? []
            users.sort { a, b in
                if a.isDriverOnline != b.isDriverOnline { return a.isDriverOnline && !b.isDriverOnline }
                let n0 = a.displayName ?? a.email ?? a.id
                let n1 = b.displayName ?? b.email ?? b.id
                return n0.localizedCaseInsensitiveCompare(n1) == .orderedAscending
            }
            continuation.yield(users)
        }
        continuation.onTermination = { @Sendable _ in listener.remove() }
        return stream
        #else
        return AsyncStream { $0.finish() }
        #endif
    }

    func approveDriver(userId: String) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore().collection("users").document(userId)
            .updateData(["isApproved": true])
        #endif
    }

    func rejectDriver(userId: String) async throws {
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore().collection("users").document(userId).delete()
        #endif
    }

    func applyAsDriver() async throws {
        #if canImport(FirebaseFirestore)
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await Firestore.firestore().collection("users").document(uid)
            .updateData([
                "role": "DRIVER",
                "isDriver": true,
                "isApproved": false,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        cachedUser = nil
        #endif
    }

    func signOut() async {
        try? Auth.auth().signOut()
        cachedUser = nil
    }

    // MARK: - Helpers

    private func buildResult(_ firebaseUser: FirebaseAuth.User, role: UserRole? = nil, referredBy: String? = nil) async throws -> (AuthSession, User) {
        let idToken = try await firebaseUser.getIDToken()
        let session = AuthSession(accessToken: idToken, refreshToken: nil, userId: firebaseUser.uid)
        let resolvedRole = role ?? defaultRole

        // Fire Firestore write in background — never block sign-in waiting for network.
        // ref.getDocument() hangs indefinitely when Firestore is unreachable; making
        // this fire-and-forget ensures sign-in always completes promptly.
        Task { await upsertFirestoreUser(firebaseUser, role: resolvedRole, referredBy: referredBy) }

        // Fetch user with a 5-second timeout. Firestore does not support cooperative
        // Swift-task cancellation, so we race two Tasks to a single-fire continuation.
        // If Firestore is slow, falls back to Firebase Auth data via mapUser.
        let fetchedUser = await fetchUserFromFirestoreWithTimeout(firebaseUser, timeout: 5)

        var user: User
        if let fetchedUser {
            user = fetchedUser
        } else {
            user = await mapUser(firebaseUser)
        }
        if let role {
            user.role = role
        }
        cachedUser = user
        return (session, user)
    }

    /// Races a Firestore fetch against a wall-clock timeout.
    /// Returns `nil` (falls back to mapUser) if Firestore doesn't respond in time.
    /// Uses `withCheckedContinuation` + `NSLock` because Firestore's `getDocument()`
    /// does not cooperate with Swift task cancellation.
    private func fetchUserFromFirestoreWithTimeout(_ firebaseUser: FirebaseAuth.User, timeout: Double) async -> User? {
        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var resumed = false

            func resumeOnce(_ value: User?) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }

            Task { resumeOnce(await self.fetchUserFromFirestore(firebaseUser)) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                resumeOnce(nil)
            }
        }
    }

    private func mapUser(_ firebaseUser: FirebaseAuth.User, role: UserRole? = nil) async -> User {
        await MainActor.run {
            User(
                id: firebaseUser.uid,
                email: firebaseUser.email,
                displayName: firebaseUser.displayName,
                phoneNumber: firebaseUser.phoneNumber,
                photoURL: firebaseUser.photoURL,
                role: role ?? defaultRole
            )
        }
    }

    nonisolated private static func decodeAvailability(_ raw: Any?) -> [String: AvailabilitySlot] {
        guard let dict = raw as? [String: [String: Any]] else { return [:] }
        var result: [String: AvailabilitySlot] = [:]
        for (day, value) in dict {
            result[day] = AvailabilitySlot(
                isEnabled: value["isEnabled"] as? Bool   ?? true,
                startTime: value["startTime"] as? String ?? "08:00",
                endTime:   value["endTime"]   as? String ?? "17:00"
            )
        }
        return result
    }

    /// Maps a Firestore `users` document to `User`. Used for reads and admin directory listener.
    nonisolated private static func makeUserFromFirestore(
        id: String,
        data: [String: Any],
        defaultRoleWhenUnknown: UserRole,
        emailFallback: String? = nil,
        displayNameFallback: String? = nil,
        phoneFallback: String? = nil,
        photoFallback: URL? = nil
    ) -> User {
        let roleStr = (data["role"] as? String ?? "").uppercased()
        let isDriverField = data["isDriver"] as? Bool
        let isCustomerField = data["isCustomer"] as? Bool
        let role: UserRole
        switch roleStr {
        case "ADMIN": role = .admin
        default:
            // Prefer the new boolean fields; fall back to legacy role string, then appMode default
            if let isDriver = isDriverField, isDriver && defaultRoleWhenUnknown == .driver {
                role = .driver
            } else if let isCustomer = isCustomerField, isCustomer && defaultRoleWhenUnknown == .customer {
                role = .customer
            } else if roleStr == "DRIVER" {
                role = defaultRoleWhenUnknown == .driver ? .driver : defaultRoleWhenUnknown
            } else {
                role = defaultRoleWhenUnknown
            }
        }
        let isOnline = data["isOnline"] as? Bool ?? false
        let home = data["homeAddress"] as? String
        let work = data["workAddress"] as? String
        let recentAddresses = data["recentAddresses"] as? [String] ?? []
        let preferredLanguage = data["preferredLanguage"] as? String
        let marketingOptIn = data["marketingOptIn"] as? Bool
        let hasCompletedOnboarding = data["hasCompletedOnboarding"] as? Bool ?? false
        let isDriverAccount = (isDriverField ?? (roleStr == "DRIVER"))
        let isApproved = isDriverAccount ? (data["isApproved"] as? Bool ?? false) : true
        let referralCode = data["referralCode"] as? String ?? ""
        let rideCredits = data["rideCredits"] as? Double ?? 0
        let referredBy = data["referredBy"] as? String
        let photoURLFromFirestore = (data["photoURL"] as? String).flatMap { URL(string: $0) }
        let availabilityEnabled = data["availabilityEnabled"] as? Bool ?? false
        let weeklyAvailability = Self.decodeAvailability(data["availability"])
        let vehicle = VehicleInfo(
            vehicleType: data["vehicleType"] as? String,
            licensePlate: data["licensePlate"] as? String
        )
        let rating = data["rating"] as? Double
        let completedRides = data["completedRides"] as? Int ?? 0
        let emailFromData = (data["email"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let displayNameFromData = (data["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let phoneFromData = (data["phoneNumber"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return User(
            id: id,
            email: emailFromData ?? emailFallback,
            displayName: displayNameFromData ?? displayNameFallback,
            phoneNumber: phoneFromData ?? phoneFallback,
            photoURL: photoURLFromFirestore ?? photoFallback,
            role: role,
            isDriverOnline: isOnline,
            vehicle: vehicle,
            savedPlaces: SavedPlaces(home: home, work: work, recentAddresses: recentAddresses),
            preferences: UserPreferences(preferredLanguage: preferredLanguage, marketingOptIn: marketingOptIn),
            rating: rating,
            completedRides: completedRides,
            hasCompletedOnboarding: hasCompletedOnboarding,
            isApproved: isApproved,
            referralCode: referralCode,
            rideCredits: rideCredits,
            referredBy: referredBy,
            weeklyAvailability: weeklyAvailability,
            availabilityEnabled: availabilityEnabled
        )
    }

    private func cachedOrCurrentUser() async throws -> User? {
        if let cached = cachedUser { return cached }
        guard let firebaseUser = Auth.auth().currentUser else { return nil }
        if let fetched = await fetchUserFromFirestore(firebaseUser) {
            cachedUser = fetched
            return fetched
        }
        return await mapUser(firebaseUser)
    }
}

enum AuthError: LocalizedError {
    case notAuthenticated
    case missingToken

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Niet ingelogd"
        case .missingToken: return "Authenticatietoken ontbreekt"
        }
    }
}
