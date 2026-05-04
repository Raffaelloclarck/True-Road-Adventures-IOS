import SwiftUI

// AuthFlowView is kept as a fallback but navigation now goes through
// WelcomeView -> LoginView / RegisterView
struct AuthFlowView: View {
    let appMode: AppMode

    var body: some View {
        WelcomeView(appMode: appMode)
    }
}

#Preview {
    AuthFlowView(appMode: .customer)
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
}
