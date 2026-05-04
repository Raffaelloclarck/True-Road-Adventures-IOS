import SwiftUI

struct RiderPromotionsView: View {
    let currentUser: User

    @State private var promoCode = ""
    @State private var isApplying = false
    @State private var resultMessage: PromoResult? = nil
    @State private var showCopied = false

    struct PromoResult: Identifiable {
        let id = UUID()
        let message: String
        let isSuccess: Bool
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                creditsCard
                referralCard
                promoEntry
                activePromos
            }
            .padding(16)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle("Promoties")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            resultMessage?.isSuccess == true ? "Gelukt!" : "Niet geldig",
            isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })
        ) {
            Button("OK") { resultMessage = nil }
        } message: {
            Text(resultMessage?.message ?? "")
        }
    }

    // MARK: - Credits balance card

    private var creditsCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColors.boltGreen)
                    .frame(width: 52, height: 52)
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Beschikbaar tegoed")
                    .font(AppFont.labelMedium())
                    .foregroundStyle(AppColors.gray500)
                Text("SRD \(currentUser.rideCredits, specifier: "%.2f")")
                    .font(AppFont.titleLarge())
                    .foregroundStyle(AppColors.gray900)
            }
            Spacer()
            if currentUser.rideCredits > 0 {
                Text("Actief")
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.boltGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppColors.boltGreenLight)
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    // MARK: - Personal referral code card

    private var referralCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.boltGreenLight)
                        .frame(width: 44, height: 44)
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(AppColors.boltGreen)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Jouw referral code")
                        .font(AppFont.titleSmall())
                        .foregroundStyle(AppColors.gray900)
                    Text("Verdien SRD 10 per vriend die zich aanmeldt")
                        .font(AppFont.bodySmall())
                        .foregroundStyle(AppColors.gray500)
                }
            }

            let code = currentUser.referralCode.isEmpty ? "TRA-??????" : currentUser.referralCode
            HStack(spacing: 10) {
                Text(code)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(AppColors.boltGreen)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    UIPasteboard.general.string = code
                    withAnimation { showCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showCopied = false }
                    }
                } label: {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.boltGreen)
                }

                ShareLink(
                    item: "Gebruik mijn referral code \(code) bij True Road Adventures en ontvang korting op je eerste rit! 🚗"
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.boltGreen)
                }
            }
            .padding(12)
            .background(AppColors.boltGreenLight)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r12))
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    // MARK: - Promo code entry

    private var promoEntry: some View {
        VStack(spacing: 12) {
            Text("Promotiecode invoeren")
                .font(AppFont.titleSmall())
                .foregroundStyle(AppColors.gray900)
                .frame(maxWidth: .infinity, alignment: .leading)
            TRATextField(placeholder: "Code invoeren", text: $promoCode, icon: "tag.fill")
            TRAPrimaryButton(
                title: "Toepassen",
                isLoading: isApplying,
                isDisabled: promoCode.trimmingCharacters(in: .whitespaces).isEmpty
            ) {
                applyPromoCode()
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    // MARK: - Active promotions

    private var activePromos: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actieve promoties")
                .font(AppFont.titleSmall())
                .foregroundStyle(AppColors.gray900)

            promoCard(
                icon: "gift.fill",
                title: "Welkomstkorting",
                subtitle: "SRD 5 korting op je eerste rit",
                expiry: "Verloopt: 31 dec 2025"
            )
            promoCard(
                icon: "person.2.fill",
                title: "Referralbonus",
                subtitle: "Nodig vrienden uit voor SRD 10 tegoed per persoon",
                expiry: "Geen vervaldatum"
            )
        }
    }

    private func promoCard(icon: String, title: String, subtitle: String, expiry: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColors.boltGreenLight)
                    .frame(width: 44, height: 44)
                Image(systemName: icon).foregroundStyle(AppColors.boltGreen)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AppFont.titleSmall()).foregroundStyle(AppColors.gray900)
                Text(subtitle).font(AppFont.bodySmall()).foregroundStyle(AppColors.gray700)
                Text(expiry).font(AppFont.labelSmall()).foregroundStyle(AppColors.gray500)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    // MARK: - Promo code logic

    private func applyPromoCode() {
        let code = promoCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard !code.isEmpty else { return }
        isApplying = true
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                isApplying = false
                promoCode = ""
                if ["WELCOME5", "TRUEROADNL", "NEWUSER"].contains(code) {
                    resultMessage = PromoResult(message: "Code '\(code)' is toegepast! Korting wordt verrekend bij je volgende rit.", isSuccess: true)
                } else {
                    resultMessage = PromoResult(message: "De code '\(code)' is niet geldig of al gebruikt.", isSuccess: false)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RiderPromotionsView(
            currentUser: User(id: "demo", email: "demo@test.nl", displayName: "Demo", role: .customer, referralCode: "TRA-AB12CD", rideCredits: 25.0)
        )
    }
}
