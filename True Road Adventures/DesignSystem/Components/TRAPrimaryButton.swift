import SwiftUI

struct TRAPrimaryButton: View {
    let title: LocalizedStringKey
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                } else {
                    Text(title)
                        .font(AppFont.labelLarge())
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                isDisabled
                    ? AppColors.boltGreen.opacity(0.4)
                    : AppColors.boltGreen
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
            .shadow(
                color: AppColors.boltGreen.opacity(isDisabled ? 0 : 0.3),
                radius: 4, x: 0, y: 4
            )
        }
        .disabled(isDisabled || isLoading)
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 16) {
        TRAPrimaryButton(title: "Rit aanvragen") {}
        TRAPrimaryButton(title: "Laden...", isLoading: true) {}
        TRAPrimaryButton(title: "Uitgeschakeld", isDisabled: true) {}
    }
    .padding()
}
