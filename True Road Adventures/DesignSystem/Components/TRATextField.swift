import SwiftUI

struct TRATextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var icon: String? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isFocused ? AppColors.boltGreen : AppColors.gray500)
                    .frame(width: 20)
            }
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .sentences)
                        .autocorrectionDisabled(keyboardType == .emailAddress)
                }
            }
            .font(AppFont.bodyLarge())
            .foregroundStyle(AppColors.gray900)
            .focused($isFocused)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(isFocused ? Color.white : AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.r16)
                .strokeBorder(
                    isFocused ? AppColors.boltGreen : AppColors.gray300,
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

#Preview {
    @Previewable @State var email = ""
    @Previewable @State var password = ""
    VStack(spacing: 12) {
        TRATextField(placeholder: "E-mailadres", text: $email,
                     keyboardType: .emailAddress, icon: "envelope")
        TRATextField(placeholder: "Wachtwoord", text: $password,
                     isSecure: true, icon: "lock")
    }
    .padding()
}
