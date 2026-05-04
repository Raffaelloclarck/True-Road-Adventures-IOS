import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.r20)
                    .fill(AppColors.boltGreenLight)
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(AppColors.boltGreen)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(AppFont.titleMedium())
                    .foregroundStyle(AppColors.gray900)

                Text(subtitle)
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(AppColors.gray500)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                TRAPrimaryButton(title: actionTitle, action: action)
                    .frame(maxWidth: 200)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

#Preview {
    VStack(spacing: 32) {
        EmptyStateView(
            icon: "car.fill",
            title: "Geen ritten",
            subtitle: "Je hebt nog geen ritten gemaakt",
            actionTitle: "Plan een rit"
        ) {}

        EmptyStateView(
            icon: "wifi.slash",
            title: "Geen verbinding",
            subtitle: "Controleer je internetverbinding"
        )
    }
    .padding()
}
