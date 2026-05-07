import Foundation
import Combine
#if canImport(FirebaseFirestore)
import FirebaseFirestore
import FirebaseAuth
#endif
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

@MainActor
final class DiscountCodeService: ObservableObject {
    @Published private(set) var allCodes: [DiscountCode] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private var listener: Any?

    // MARK: - Admin: stream all codes

    func startListening() {
        #if canImport(FirebaseFirestore)
        stopListening()
        isLoading = true
        let db = Firestore.firestore()
        listener = db.collection("discountCodes")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, err in
                guard let self else { return }
                self.isLoading = false
                if let err {
                    self.error = err.localizedDescription
                    return
                }
                self.allCodes = snapshot?.documents.compactMap {
                    discountCodeFromDocument(id: $0.documentID, data: $0.data())
                } ?? []
            }
        #endif
    }

    func stopListening() {
        #if canImport(FirebaseFirestore)
        if let l = listener as? ListenerRegistration { l.remove() }
        listener = nil
        #endif
    }

    // MARK: - Admin: CRUD

    func createCode(_ code: DiscountCode) async throws {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let ref = db.collection("discountCodes").document()
        var data: [String: Any] = [
            "code":              code.code.uppercased(),
            "type":              code.type.rawValue,
            "value":             code.value,
            "expiresAt":         Int64(code.expiresAt.timeIntervalSince1970 * 1000),
            "isActive":          code.isActive,
            "currentUses":       0,
            "oncePerUser":       code.oncePerUser,
            "usedByUserIds":     [String](),
            "createdAt":         Int64(Date().timeIntervalSince1970 * 1000),
            "createdByAdminId":  code.createdByAdminId,
        ]
        if let max = code.maxUses    { data["maxUses"]     = max }
        if let min = code.minFare    { data["minFare"]     = min }
        if let desc = code.description, !desc.isEmpty { data["description"] = desc }
        try await ref.setData(data)
        #endif
    }

    func toggleActive(_ code: DiscountCode) async throws {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        try await db.collection("discountCodes").document(code.id).updateData([
            "isActive": !code.isActive
        ])
        #endif
    }

    func deleteCode(_ code: DiscountCode) async throws {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        try await db.collection("discountCodes").document(code.id).delete()
        #endif
    }

    // MARK: - Rider: fetch active codes for display

    /// Returns all active, non-expired discount codes for display in the
    /// Promotions tab. Firestore filters by `isActive == true`; expiry is
    /// checked client-side so no composite index is needed.
    func fetchActiveCodesForRider() async throws -> [DiscountCode] {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let snapshot = try await db.collection("discountCodes")
            .whereField("isActive", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        let now = Date()
        return snapshot.documents.compactMap {
            discountCodeFromDocument(id: $0.documentID, data: $0.data())
        }.filter { $0.expiresAt > now }
        #else
        return []
        #endif
    }

    // MARK: - Rider: preview discount (read-only, does not consume the code)

    /// Fetches the code from Firestore and computes the discount amount locally
    /// without calling the Cloud Function and without modifying anything.
    /// Throws the same error strings as the CF so existing error-message handling works.
    func previewDiscount(_ code: String, fare: Double) async throws -> RedeemResult {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let snapshot = try await db.collection("discountCodes")
            .whereField("code", isEqualTo: code.uppercased())
            .limit(to: 1)
            .getDocuments()
        guard let doc = snapshot.documents.first,
              let discountCode = discountCodeFromDocument(id: doc.documentID, data: doc.data())
        else {
            throw PreviewError.invalid
        }
        guard discountCode.isActive else { throw PreviewError.invalid }
        guard discountCode.expiresAt > Date() else { throw PreviewError.expired }
        if let max = discountCode.maxUses, discountCode.currentUses >= max {
            throw PreviewError.maxUsesReached
        }
        if discountCode.oncePerUser,
           let uid = Auth.auth().currentUser?.uid,
           discountCode.usedByUserIds.contains(uid) {
            throw PreviewError.alreadyUsed
        }
        if let min = discountCode.minFare, fare < min {
            throw PreviewError.minFareNotMet
        }
        let discountAmount: Double
        switch discountCode.type {
        case .percentage:
            discountAmount = (fare * discountCode.value / 100).rounded(.down)
        case .fixed:
            discountAmount = min(discountCode.value, fare)
        }
        return RedeemResult(type: discountCode.type, value: discountCode.value, discountAmount: discountAmount)
        #else
        throw DiscountCodeError.notAvailable
        #endif
    }

    private enum PreviewError: LocalizedError {
        case invalid, expired, maxUsesReached, alreadyUsed, minFareNotMet
        var errorDescription: String? {
            switch self {
            case .invalid:         return "discount.code.invalid"
            case .expired:         return "discount.code.expired"
            case .maxUsesReached:  return "discount.code.max_uses_reached"
            case .alreadyUsed:     return "discount.code.already_used"
            case .minFareNotMet:   return "discount.code.min_fare"
            }
        }
    }

    // MARK: - Rider: redeem via Cloud Function

    struct RedeemResult {
        let type: DiscountCodeType
        let value: Double
        let discountAmount: Double
    }

    func redeemCode(_ code: String, context: RedeemContext, fare: Double?) async throws -> RedeemResult {
        #if canImport(FirebaseFunctions)
        let functions = Functions.functions()
        let callable = functions.httpsCallable("redeemDiscountCode")
        var params: [String: Any] = [
            "code":    code.uppercased(),
            "context": context.rawValue,
        ]
        if let fare { params["fare"] = fare }
        let response = try await callable.call(params)
        guard let data = response.data as? [String: Any],
              let typeStr = data["type"] as? String,
              let type = DiscountCodeType(rawValue: typeStr),
              let value = (data["value"] as? NSNumber)?.doubleValue,
              let discount = (data["discountAmount"] as? NSNumber)?.doubleValue
        else {
            throw DiscountCodeError.invalidResponse
        }
        return RedeemResult(type: type, value: value, discountAmount: discount)
        #else
        throw DiscountCodeError.notAvailable
        #endif
    }

    enum RedeemContext: String {
        case ride = "ride"
        case credits = "credits"
    }

    enum DiscountCodeError: LocalizedError {
        case invalidResponse
        case notAvailable
        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Ongeldig antwoord van server."
            case .notAvailable:    return "Functie niet beschikbaar in deze build."
            }
        }
    }
}

// MARK: - Firestore document parsing

private func discountCodeFromDocument(id: String, data: [String: Any]) -> DiscountCode? {
    guard
        let code    = data["code"] as? String,
        let typeStr = data["type"] as? String,
        let type    = DiscountCodeType(rawValue: typeStr),
        let value   = (data["value"] as? NSNumber)?.doubleValue,
        let expiresAtMs = (data["expiresAt"] as? NSNumber)?.doubleValue,
        let createdAtMs = (data["createdAt"] as? NSNumber)?.doubleValue,
        let adminId = data["createdByAdminId"] as? String
    else { return nil }

    let isActive     = data["isActive"] as? Bool ?? false
    let currentUses  = (data["currentUses"] as? NSNumber)?.intValue ?? 0
    let oncePerUser  = data["oncePerUser"] as? Bool ?? false
    let usedByIds    = data["usedByUserIds"] as? [String] ?? []
    let maxUses      = (data["maxUses"] as? NSNumber)?.intValue
    let minFare      = (data["minFare"] as? NSNumber)?.doubleValue
    let description  = data["description"] as? String

    return DiscountCode(
        id:               id,
        code:             code,
        type:             type,
        value:            value,
        expiresAt:        Date(timeIntervalSince1970: expiresAtMs / 1000),
        isActive:         isActive,
        maxUses:          maxUses,
        currentUses:      currentUses,
        oncePerUser:      oncePerUser,
        usedByUserIds:    usedByIds,
        minFare:          minFare,
        description:      description,
        createdAt:        Date(timeIntervalSince1970: createdAtMs / 1000),
        createdByAdminId: adminId
    )
}
