import SwiftUI

struct RiderSafetyInfoView: View {
    @State private var showSOSAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sosButton

                safetySection(
                    icon: "shield.fill",
                    title: "Noodknop",
                    description: "Neem in geval van nood direct contact op met hulpdiensten. Druk op de noodknop in de rit-weergave."
                )
                safetySection(
                    icon: "location.fill",
                    title: "Locatie delen",
                    description: "Deel je rit-locatie met familie en vrienden voor extra veiligheid."
                )
                safetySection(
                    icon: "star.fill",
                    title: "Beoordeel je chauffeur",
                    description: "Help ons de kwaliteit te verbeteren door na elke rit een beoordeling te geven."
                )
                safetySection(
                    icon: "phone.fill",
                    title: "24/7 support",
                    description: "Ons ondersteuningsteam is dag en nacht bereikbaar voor vragen en noodgevallen."
                )

                contactButtons
            }
            .padding(16)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle("Veiligheid")
        .navigationBarTitleDisplayMode(.inline)
        .alert("112 Bellen?", isPresented: $showSOSAlert) {
            Button("Bel 112", role: .destructive) {
                if let url = URL(string: "tel://112") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("Je staat op het punt de nooddiensten te bellen. Weet je zeker dat je door wilt gaan?")
        }
    }

    private var sosButton: some View {
        Button {
            showSOSAlert = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sos")
                    .font(.system(size: 22, weight: .bold))
                Text("Noodknop – Bel 112")
                    .font(AppFont.titleSmall())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppColors.errorRed)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        }
        .buttonStyle(.plain)
    }

    private var contactButtons: some View {
        VStack(spacing: 10) {
            TRAPrimaryButton(title: "Chat met support") {
                if let url = URL(string: "mailto:support@trueroadadventures.nl") {
                    UIApplication.shared.open(url)
                }
            }
            TRASecondaryButton(title: "Bel support", icon: "phone.fill") {
                if let url = URL(string: "tel://+31201234567") {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private func safetySection(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColors.boltGreen.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundStyle(AppColors.boltGreen)
            }
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(AppFont.titleSmall())
                    .foregroundStyle(AppColors.gray900)
                Text(description)
                    .font(AppFont.bodySmall())
                    .foregroundStyle(AppColors.gray500)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }
}

#Preview { NavigationStack { RiderSafetyInfoView() } }
