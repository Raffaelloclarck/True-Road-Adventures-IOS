import SwiftUI

struct WelcomeView: View {
    let appMode: AppMode
    @EnvironmentObject private var authService: AuthService
    @State private var path = NavigationPath()
    @State private var appleCoordinator: AppleSignInCoordinator?

    private var heroColor: Color {
        appMode == .driver ? AppColors.boltGreenDeep : AppColors.boltGreen
    }
    private var heroHeight: CGFloat {
        appMode == .driver ? 320 : 300
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    heroSection
                    Color.white
                }
                .ignoresSafeArea()

                bottomCard
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationBarHidden(true)
            .navigationDestination(for: AuthDestination.self) { dest in
                switch dest {
                case .login:
                    LoginView(appMode: appMode, path: $path)
                case .register:
                    RegisterView(appMode: appMode, path: $path)
                case .phone:
                    PhoneAuthView(path: $path)
                }
            }
        }
    }

    private var heroSection: some View {
        ZStack {
            heroColor.ignoresSafeArea()

            if appMode == .driver {
                VStack(spacing: 8) {
                    Text("🚗")
                        .font(.system(size: 64))
                    VStack(spacing: 2) {
                        Text("True Road")
                            .font(AppFont.headlineMedium())
                            .foregroundStyle(.white)
                        Text("Driver")
                            .font(AppFont.headlineMedium())
                            .foregroundStyle(AppColors.boltGreen)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Text("🛣️")
                        .font(.system(size: 64))
                    Text("True Road Adventures")
                        .font(AppFont.headlineMedium())
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(height: heroHeight)
    }

    private var bottomCard: some View {
        VStack(spacing: 16) {
            phoneButton
            Divider()
                .overlay(
                    HStack {
                        Rectangle().fill(AppColors.gray300).frame(height: 1)
                        Text("welcome.or")
                            .font(AppFont.labelMedium())
                            .foregroundStyle(AppColors.gray500)
                            .padding(.horizontal, 12)
                        Rectangle().fill(AppColors.gray300).frame(height: 1)
                    }
                )
                .padding(.horizontal, 4)

            TRASecondaryButton(title: "welcome.cta.google", icon: "globe") {
                Task { await signInWithGoogle(authService: authService) }
            }
            TRASecondaryButton(title: "welcome.cta.apple", icon: "apple.logo") {
                handleAppleSignIn()
            }
            TRASecondaryButton(title: "welcome.cta.email", icon: "envelope") {
                path.append(AuthDestination.login)
            }

            legalText

            HStack {
                Text("welcome.no_account")
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(AppColors.gray500)
                Button {
                    path.append(AuthDestination.register)
                } label: {
                    Text("welcome.register")
                        .font(AppFont.labelMedium())
                        .foregroundStyle(AppColors.boltGreen)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 32)
        .background(
            Color.white
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: AppRadius.r28,
                        topTrailingRadius: AppRadius.r28
                    )
                )
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4)
        )
        .offset(y: -20)
    }

    private var phoneButton: some View {
        TRAPrimaryButton(title: "welcome.cta.phone") {
            path.append(AuthDestination.phone)
        }
    }

    private var legalText: some View {
        Text("\(Text("welcome.legal.pre")) \(Text("welcome.terms").foregroundStyle(AppColors.boltGreen)) \(Text("welcome.legal.and")) \(Text("welcome.privacy").foregroundStyle(AppColors.boltGreen))")
            .foregroundStyle(AppColors.gray500)
            .font(AppFont.bodySmall())
            .multilineTextAlignment(.center)
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

enum AuthDestination: Hashable {
    case login, register, phone
}

#Preview("Customer") {
    WelcomeView(appMode: .customer)
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
}

#Preview("Driver") {
    WelcomeView(appMode: .driver)
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
}
