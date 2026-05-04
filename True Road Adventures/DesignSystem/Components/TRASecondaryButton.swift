import SwiftUI

struct TRASecondaryButton: View {
    let title: LocalizedStringKey
    var isDisabled: Bool = false
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(AppFont.labelLarge())
            }
            .foregroundStyle(isDisabled ? AppColors.boltGreen.opacity(0.4) : AppColors.boltGreen)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.r16)
                    .strokeBorder(
                        isDisabled ? AppColors.boltGreen.opacity(0.4) : AppColors.boltGreen,
                        lineWidth: 1.5
                    )
            )
        }
        .disabled(isDisabled)
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 16) {
        TRASecondaryButton(title: "Inloggen met Google", icon: "globe") {}
        TRASecondaryButton(title: "Uitgeschakeld", isDisabled: true) {}
    }
    .padding()
}
