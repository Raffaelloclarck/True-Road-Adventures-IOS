import SwiftUI

struct PhoneAuthView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var authService: AuthService

    @State private var countryCode = "+31"
    @State private var phoneNumber = ""
    @State private var otpCode = ""
    @State private var verificationID: String?
    @State private var isLoading = false

    private var isStep2: Bool { verificationID != nil }

    private var fullPhoneNumber: String {
        let digits = phoneNumber.filter(\.isNumber)
        return countryCode + digits
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppColors.boltGreen.ignoresSafeArea()

            VStack(spacing: 0) {
                heroStrip.frame(height: 180)
                formCard.offset(y: -32)
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Hero

    private var heroStrip: some View {
        ZStack(alignment: .topLeading) {
            AppColors.boltGreen

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    if isStep2 {
                        verificationID = nil
                        otpCode = ""
                    } else {
                        path.removeLast()
                    }
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(isStep2 ? "phone.title.step2" : "phone.title.step1")
                        .font(AppFont.headlineSmall())
                        .foregroundStyle(.white)
                    Text(isStep2 ? "phone.step2.label" : "phone.step1.label")
                        .font(AppFont.bodySmall())
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Form

    private var formCard: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isStep2 {
                    otpStep
                } else {
                    phoneStep
                }

                if let error = authService.state.error {
                    errorBanner(error)
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

    private var phoneStep: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("phone.step1.label")
                    .font(AppFont.labelMedium())
                    .foregroundStyle(AppColors.gray700)

                HStack(spacing: 8) {
                    countryCodePicker
                    TRATextField(
                        placeholder: "phone.step1.placeholder",
                        text: $phoneNumber,
                        keyboardType: .phonePad,
                        icon: "phone"
                    )
                }
            }

            Text("phone.step1.subtitle")
                .font(AppFont.bodySmall())
                .foregroundStyle(AppColors.gray500)
                .frame(maxWidth: .infinity, alignment: .leading)

            TRAPrimaryButton(title: "phone.step1.cta", isLoading: isLoading) {
                sendCode()
            }
            .disabled(phoneNumber.filter(\.isNumber).count < 8)
        }
    }

    private var otpStep: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("phone.step2.field.title")
                    .font(AppFont.labelMedium())
                    .foregroundStyle(AppColors.gray700)

                TRATextField(
                    placeholder: "phone.step2.placeholder",
                    text: $otpCode,
                    keyboardType: .numberPad,
                    icon: "key"
                )
            }

            Text("phone.step2.subtitle \(fullPhoneNumber).")
                .font(AppFont.bodySmall())
                .foregroundStyle(AppColors.gray500)
                .frame(maxWidth: .infinity, alignment: .leading)

            TRAPrimaryButton(title: "phone.step2.cta", isLoading: isLoading) {
                verifyCode()
            }
            .disabled(otpCode.count < 6)

            Button {
                verificationID = nil
                otpCode = ""
                sendCode()
            } label: {
                Text("phone.step2.resend")
                    .font(AppFont.labelMedium())
                    .foregroundStyle(AppColors.boltGreen)
            }
        }
    }

    private var countryCodePicker: some View {
        Menu {
            ForEach(PhoneCountryCode.all) { item in
                Button("\(item.flag) \(item.name) (\(item.code))") {
                    countryCode = item.code
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(countryCode)
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(AppColors.gray900)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.gray500)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(AppColors.gray100)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r12))
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

    // MARK: - Actions

    private func sendCode() {
        isLoading = true
        Task {
            do {
                let id = try await authService.sendVerificationCode(to: fullPhoneNumber)
                await MainActor.run {
                    verificationID = id
                    isLoading = false
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }

    private func verifyCode() {
        guard let id = verificationID else { return }
        isLoading = true
        Task {
            do {
                try await authService.verifyPhoneCode(otpCode, verificationID: id)
            } catch {}
            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - Country codes

struct PhoneCountryCode: Identifiable {
    let id: String
    let flag: String
    let name: String
    let code: String

    static let all: [PhoneCountryCode] = [
        .init(id: "NL", flag: "🇳🇱", name: String(localized: "phone.country.nl"), code: "+31"),
        .init(id: "BE", flag: "🇧🇪", name: String(localized: "phone.country.be"), code: "+32"),
        .init(id: "DE", flag: "🇩🇪", name: String(localized: "phone.country.de"), code: "+49"),
        .init(id: "FR", flag: "🇫🇷", name: String(localized: "phone.country.fr"), code: "+33"),
        .init(id: "GB", flag: "🇬🇧", name: String(localized: "phone.country.gb"), code: "+44"),
        .init(id: "US", flag: "🇺🇸", name: String(localized: "phone.country.us"), code: "+1"),
        .init(id: "ES", flag: "🇪🇸", name: String(localized: "phone.country.es"), code: "+34"),
        .init(id: "IT", flag: "🇮🇹", name: String(localized: "phone.country.it"), code: "+39"),
        .init(id: "PL", flag: "🇵🇱", name: String(localized: "phone.country.pl"), code: "+48"),
        .init(id: "TR", flag: "🇹🇷", name: String(localized: "phone.country.tr"), code: "+90"),
        .init(id: "MA", flag: "🇲🇦", name: String(localized: "phone.country.ma"), code: "+212"),
        .init(id: "NG", flag: "🇳🇬", name: String(localized: "phone.country.ng"), code: "+234"),
    ]
}

#Preview {
    @Previewable @State var path = NavigationPath()
    PhoneAuthView(path: $path)
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
}
