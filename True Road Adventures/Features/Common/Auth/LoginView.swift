import SwiftUI

struct LoginView: View {
    let appMode: AppMode
    @Binding var path: NavigationPath

    @EnvironmentObject private var authService: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showForgotPassword = false
    @State private var forgotEmail = ""
    @State private var forgotSent = false
    @State private var appleCoordinator: AppleSignInCoordinator?

    var body: some View {
        ZStack(alignment: .top) {
            AppColors.boltGreen.ignoresSafeArea()

            VStack(spacing: 0) {
                heroStrip
                    .frame(height: 180)

                formCard
                    .offset(y: -32)
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .alert(Text("login.reset.alert.title"), isPresented: $showForgotPassword) {
            TextField(text: $forgotEmail) {
                Text("login.reset.email.placeholder")
            }
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            Button(role: .cancel) { forgotEmail = "" } label: { Text("login.reset.cancel") }
            Button { sendPasswordReset() } label: { Text("login.reset.send") }
        } message: {
            Text("login.reset.alert.body")
        }
        .alert(Text("login.reset.success.title"), isPresented: $forgotSent) {
            Button(role: .cancel) {} label: { Text("login.ok") }
        } message: {
            Text("login.reset.success.body")
        }
    }

    private var heroStrip: some View {
        ZStack(alignment: .topLeading) {
            AppColors.boltGreen

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    path.removeLast()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .padding(.top, 56)
                .padding(.leading, 24)

                Spacer()

                Text("login.title")
                    .font(AppFont.headlineSmall())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
        }
    }

    private var formCard: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    TRATextField(
                        placeholder: "login.email.placeholder",
                        text: $email,
                        keyboardType: .emailAddress,
                        icon: "envelope"
                    )
                    TRATextField(
                        placeholder: "login.password.placeholder",
                        text: $password,
                        isSecure: true,
                        icon: "lock"
                    )

                    HStack {
                        Spacer()
                        Button {
                            forgotEmail = email
                            showForgotPassword = true
                        } label: {
                            Text("login.forgot_password")
                                .font(AppFont.labelMedium())
                                .foregroundStyle(AppColors.boltGreen)
                        }
                    }
                }

                if let error = authService.state.error {
                    errorBanner(error)
                }

                TRAPrimaryButton(title: "login.cta", isLoading: isLoading) {
                    submit()
                }

                divider

                TRASecondaryButton(title: "login.google", icon: "globe") {
                    Task { await signInWithGoogle(authService: authService) }
                }
                TRASecondaryButton(title: "login.apple", icon: "apple.logo") {
                    handleAppleSignIn()
                }
            }
            .padding(24)
        }
        .background(
            Color.white
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: AppRadius.r28,
                        topTrailingRadius: AppRadius.r28
                    )
                )
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var divider: some View {
        HStack {
            Rectangle().fill(AppColors.gray300).frame(height: 1)
            Text("welcome.or")
                .font(AppFont.labelMedium())
                .foregroundStyle(AppColors.gray500)
                .padding(.horizontal, 12)
            Rectangle().fill(AppColors.gray300).frame(height: 1)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(AppColors.errorRed)
            Text(message)
                .font(AppFont.bodyMedium())
                .foregroundStyle(AppColors.errorRed)
            Spacer()
        }
        .padding(12)
        .background(AppColors.errorRed.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r12))
    }

    private func submit() {
        isLoading = true
        Task {
            do {
                try await authService.signIn(email: email, password: password)
            } catch {}
            await MainActor.run { isLoading = false }
        }
    }

    private func sendPasswordReset() {
        let emailToReset = forgotEmail
        forgotEmail = ""
        Task {
            await authService.sendPasswordReset(email: emailToReset)
            await MainActor.run { forgotSent = true }
        }
    }

    private func handleAppleSignIn() {
        let coordinator = AppleSignInCoordinator(authService: authService)
        coordinator.onComplete = { error in
            if let error {
                authService.setError(error.localizedDescription)
            }
        }
        appleCoordinator = coordinator
        coordinator.startSignIn()
    }
}

#Preview {
    @Previewable @State var path = NavigationPath()
    LoginView(appMode: .customer, path: $path)
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
}
