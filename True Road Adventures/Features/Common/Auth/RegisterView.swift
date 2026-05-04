import SwiftUI

struct RegisterView: View {
    let appMode: AppMode
    @Binding var path: NavigationPath

    @EnvironmentObject private var authService: AuthService
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var referralCode = ""
    @State private var isLoading = false

    private var role: UserRole { appMode == .driver ? .driver : .customer }

    var body: some View {
        ZStack(alignment: .top) {
            AppColors.boltGreenDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                heroStrip
                    .frame(height: 180)

                formCard
                    .offset(y: -32)
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }

    private var heroStrip: some View {
        ZStack(alignment: .topLeading) {
            AppColors.boltGreenDeep

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    path.removeLast()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .padding(.top, 56)
                .padding(.leading, 24)

                Spacer()

                Text("register.title")
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
                        placeholder: "register.name.placeholder",
                        text: $name,
                        icon: "person"
                    )
                    TRATextField(
                        placeholder: "register.email.placeholder",
                        text: $email,
                        keyboardType: .emailAddress,
                        icon: "envelope"
                    )
                    TRATextField(
                        placeholder: "register.password.placeholder",
                        text: $password,
                        isSecure: true,
                        icon: "lock"
                    )
                    TRATextField(
                        placeholder: "register.referral.placeholder",
                        text: $referralCode,
                        icon: "gift"
                    )
                }

                if let error = authService.state.error {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(AppColors.errorRed)
                        Text(error)
                            .font(AppFont.bodyMedium())
                            .foregroundStyle(AppColors.errorRed)
                        Spacer()
                    }
                    .padding(12)
                    .background(AppColors.errorRed.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.r12))
                }

                TRAPrimaryButton(title: "register.cta", isLoading: isLoading) {
                    submit()
                }

                legalText
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

    private var legalText: some View {
        Text("\(Text("register.legal.pre")) \(Text("register.terms").foregroundStyle(AppColors.boltGreen)) \(Text("register.legal.and")) \(Text("register.privacy").foregroundStyle(AppColors.boltGreen))")
            .foregroundStyle(AppColors.gray500)
            .font(AppFont.bodySmall())
            .multilineTextAlignment(.center)
    }

    private func submit() {
        isLoading = true
        Task {
            do {
                let code = referralCode.trimmingCharacters(in: .whitespaces)
                try await authService.register(
                    email: email,
                    password: password,
                    displayName: name,
                    role: role,
                    referredBy: code.isEmpty ? nil : code.uppercased()
                )
            } catch {}
            await MainActor.run { isLoading = false }
        }
    }
}

#Preview {
    @Previewable @State var path = NavigationPath()
    RegisterView(appMode: .customer, path: $path)
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
}
