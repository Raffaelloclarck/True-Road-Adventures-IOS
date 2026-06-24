import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(StripePaymentSheet)
import StripePaymentSheet
#endif
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

@MainActor
final class PaymentService {
    enum PaymentSheetResult: Sendable {
        case completed
        case canceled
        case failed(String)
    }

    private let config: AppConfig
    private let functionsRegion = "us-central1"

    init(config: AppConfig) {
        self.config = config
        #if canImport(StripePaymentSheet)
        if let key = config.paymentPublicKey, !key.isEmpty {
            STPAPIClient.shared.publishableKey = key
        }
        #endif
    }

    // MARK: - Saved cards

    func fetchSavedMethods() async throws -> [SavedPaymentMethod] {
        let result = try await callFunction("listPaymentMethods", data: [:])
        guard let methods = result["methods"] as? [[String: Any]] else { return [] }
        return methods.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let brand = dict["brand"] as? String,
                  let last4 = dict["last4"] as? String else { return nil }
            return SavedPaymentMethod(
                id: id,
                brand: brand,
                last4: last4,
                expMonth: dict["expMonth"] as? Int ?? 0,
                expYear: dict["expYear"] as? Int ?? 0
            )
        }
    }

    /// Presents Stripe SetupIntent flow to save a card for future rides.
    func addPaymentMethod() async throws {
        let result = try await callFunction("createStripeSetupIntent", data: [:])
        guard let clientSecret = result["clientSecret"] as? String else {
            throw PaymentError.invalidResponse
        }
        try await presentSetupSheet(clientSecret: clientSecret)
    }

    // MARK: - Ride payments

    /// Authorizes (holds) the estimated fare when a card ride is booked.
    func authorizeRidePayment(rideId: String, amount: Double, currency: String = "srd") async throws {
        guard amount > 0 else { return }
        guard config.paymentPublicKey != nil else {
            throw PaymentError.missingPublicKey
        }
        let result = try await callFunction("createStripePaymentIntent", data: [
            "rideId": rideId,
            "amount": amount,
            "currency": currency,
        ])
        guard let clientSecret = result["clientSecret"] as? String else {
            throw PaymentError.invalidResponse
        }
        let outcome = try await presentPaymentSheet(clientSecret: clientSecret)
        switch outcome {
        case .completed:
            return
        case .canceled:
            throw PaymentError.canceled
        case .failed(let message):
            throw PaymentError.captureFailed(message)
        }
    }

    /// Captures the held amount after the ride completes.
    func captureRidePayment(rideId: String, amount: Double) async throws {
        guard amount > 0 else { return }
        _ = try await callFunction("captureRidePayment", data: [
            "rideId": rideId,
            "amount": amount,
        ])
    }

    /// Driver confirms cash was received.
    func confirmCashPayment(rideId: String) async throws {
        _ = try await callFunction("confirmCashPayment", data: ["rideId": rideId])
    }

    // MARK: - Legacy demo entry point

    func presentPaymentSheet(amount: Double = 10.0, currency: String = "srd") async throws {
        guard config.paymentPublicKey != nil else {
            throw PaymentError.missingPublicKey
        }
        let result = try await callFunction("createStripePaymentIntent", data: [
            "amount": amount,
            "currency": currency,
        ])
        guard let clientSecret = result["clientSecret"] as? String else {
            throw PaymentError.invalidResponse
        }
        _ = try await presentPaymentSheet(clientSecret: clientSecret)
    }

    // MARK: - Private

    private func callFunction(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        #if canImport(FirebaseFunctions)
        let callable = Functions.functions(region: functionsRegion).httpsCallable(name)
        let result = try await callable.call(data)
        return result.data as? [String: Any] ?? [:]
        #else
        throw PaymentError.functionsNotLinked
        #endif
    }

    private func presentPaymentSheet(clientSecret: String) async throws -> PaymentSheetResult {
        #if canImport(StripePaymentSheet) && canImport(UIKit)
        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = "True Road Adventures"
        let paymentSheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: configuration)
        guard let controller = keyViewController() else {
            throw PaymentError.noViewController
        }
        return try await withCheckedThrowingContinuation { continuation in
            paymentSheet.present(from: controller) { result in
                switch result {
                case .completed:
                    continuation.resume(returning: .completed)
                case .canceled:
                    continuation.resume(returning: .canceled)
                case .failed(let error):
                    continuation.resume(returning: .failed(error.localizedDescription))
                }
            }
        }
        #else
        throw PaymentError.stripeNotLinked
        #endif
    }

    private func presentSetupSheet(clientSecret: String) async throws {
        #if canImport(StripePaymentSheet) && canImport(UIKit)
        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = "True Road Adventures"
        let setupSheet = PaymentSheet(setupIntentClientSecret: clientSecret, configuration: configuration)
        guard let controller = keyViewController() else {
            throw PaymentError.noViewController
        }
        let outcome = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PaymentSheetResult, Error>) in
            setupSheet.present(from: controller) { result in
                switch result {
                case .completed:
                    continuation.resume(returning: .completed)
                case .canceled:
                    continuation.resume(returning: .canceled)
                case .failed(let error):
                    continuation.resume(returning: .failed(error.localizedDescription))
                }
            }
        }
        switch outcome {
        case .completed: return
        case .canceled: throw PaymentError.canceled
        case .failed(let message): throw PaymentError.captureFailed(message)
        }
        #else
        throw PaymentError.stripeNotLinked
        #endif
    }

    #if canImport(UIKit)
    private func keyViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
    #endif
}

enum PaymentError: LocalizedError {
    case missingPublicKey
    case noViewController
    case stripeNotLinked
    case functionsNotLinked
    case invalidResponse
    case canceled
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPublicKey:
            return String(localized: "payment.error.missing_key")
        case .noViewController:
            return String(localized: "payment.error.no_screen")
        case .stripeNotLinked:
            return String(localized: "payment.error.stripe_not_linked")
        case .functionsNotLinked:
            return String(localized: "payment.error.functions_not_linked")
        case .invalidResponse:
            return String(localized: "payment.error.invalid_response")
        case .canceled:
            return String(localized: "payment.error.canceled")
        case .captureFailed(let message):
            return message
        }
    }
}
