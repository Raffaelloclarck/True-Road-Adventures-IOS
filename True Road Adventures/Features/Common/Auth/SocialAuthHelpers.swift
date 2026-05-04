import SwiftUI
import GoogleSignIn
import AuthenticationServices
import CryptoKit

// MARK: - Google Sign-In

@MainActor
func signInWithGoogle(authService: AuthService) async {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let root = scene.windows.first?.rootViewController else { return }
    do {
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
        guard let idToken = result.user.idToken?.tokenString else {
            authService.setError("Google-token ontbreekt")
            return
        }
        let accessToken = result.user.accessToken.tokenString
        try await authService.signInWithGoogle(idToken: idToken, accessToken: accessToken)
    } catch {
        authService.setError(error.localizedDescription)
    }
}

// MARK: - Apple Sign-In

final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let authService: AuthService
    private var rawNonce: String = ""
    var onComplete: ((Error?) -> Void)?

    init(authService: AuthService) {
        self.authService = authService
    }

    func startSignIn() {
        rawNonce = randomNonceString()
        let hashedNonce = sha256(rawNonce)

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = appleCredential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            onComplete?(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Apple-credential ontbreekt"]))
            return
        }
        let nonce = rawNonce
        Task { @MainActor in
            do {
                try await self.authService.signInWithApple(idToken: idToken, rawNonce: nonce)
                self.onComplete?(nil)
            } catch {
                self.onComplete?(error)
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        // Code 1001 = user cancelled; don't surface as an error
        if nsError.code != 1001 {
            onComplete?(error)
        } else {
            onComplete?(nil)
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
            return window
        }
        if let window = scenes.flatMap({ $0.windows }).first {
            return window
        }
        if let scene = scenes.first {
            return UIWindow(windowScene: scene)
        }
        // Unreachable on iOS 26+ where UIWindowScene is always present.
        preconditionFailure("No UIWindowScene available — cannot present Apple Sign-In")
    }

    // MARK: - Nonce helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(errorCode == errSecSuccess, "Unable to generate nonce")
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { byte in charset[Int(byte) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

