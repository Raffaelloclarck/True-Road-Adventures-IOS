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

final class PaymentService {
    private let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    func presentPaymentSheet(amount: Double = 10.0, currency: String = "srd") async throws {
        guard let key = config.paymentPublicKey, !key.isEmpty else {
            throw PaymentError.missingPublicKey
        }

        let intentSecret = try await createPaymentIntent(amount: amount, currency: currency)

        #if canImport(StripePaymentSheet) && canImport(UIKit)
        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = "True Road Adventures"
        let paymentSheet = PaymentSheet(paymentIntentClientSecret: intentSecret, configuration: configuration)
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        guard let controller = keyWindow?.rootViewController else {
            throw PaymentError.noViewController
        }
        await MainActor.run {
            paymentSheet.present(from: controller) { _ in }
        }
        #else
        throw PaymentError.stripeNotLinked
        #endif
    }

    private func createPaymentIntent(amount: Double, currency: String) async throws -> String {
        #if canImport(FirebaseFunctions)
        let functions = Functions.functions(region: "us-central1")
        let callable  = functions.httpsCallable("createStripePaymentIntent")
        let data: [String: Any] = [
            "amount":   Int(amount * 100),
            "currency": currency,
        ]
        let result = try await callable.call(data)
        guard let resultMap = result.data as? [String: Any],
              let clientSecret = resultMap["clientSecret"] as? String else {
            throw PaymentError.invalidResponse
        }
        return clientSecret
        #else
        throw PaymentError.functionsNotLinked
        #endif
    }
}

enum PaymentError: LocalizedError {
    case missingPublicKey
    case noViewController
    case stripeNotLinked
    case functionsNotLinked
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingPublicKey:
            return "Betaalsleutel ontbreekt. Controleer de app-configuratie."
        case .noViewController:
            return "Geen zichtbaar scherm voor betaling."
        case .stripeNotLinked:
            return "Stripe is niet gekoppeld. Voeg het StripePaymentSheet-pakket toe via Swift Package Manager."
        case .functionsNotLinked:
            return "FirebaseFunctions is niet gekoppeld. Voeg het toe via Swift Package Manager."
        case .invalidResponse:
            return "Ongeldig antwoord van de betalingsfunctie."
        }
    }
}
