import SwiftUI

struct AdminDiscountCodeFormView: View {
    let adminId: String
    let onSave: (DiscountCode) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var type: DiscountCodeType = .percentage
    @State private var value = ""
    @State private var expiresAt = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var maxUsesEnabled = false
    @State private var maxUsesValue = ""
    @State private var oncePerUser = false
    @State private var minFareEnabled = false
    @State private var minFareValue = ""
    @State private var descriptionText = ""
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    codeCard
                    typeValueCard
                    expiryCard
                    limitsCard
                    descriptionCard
                    if let err = validationError {
                        Text(err)
                            .font(AppFont.bodySmall())
                            .foregroundStyle(AppColors.errorRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(AppColors.backgroundLight)
            .navigationTitle("Nieuwe kortingscode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                        .foregroundStyle(AppColors.gray700)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Opslaan") { saveCode() }
                        .font(AppFont.labelMedium())
                        .foregroundStyle(AppColors.boltGreen)
                }
            }
        }
    }

    // MARK: - Cards

    private var codeCard: some View {
        formCard {
            cardRow(icon: "tag.fill") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Code")
                        .font(AppFont.labelSmall())
                        .foregroundStyle(AppColors.gray500)
                    TextField("Bijv. ZOMER20", text: $code)
                        .font(AppFont.bodyMedium())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: code) { _, new in code = new.uppercased() }
                }
            }
        }
    }

    private var typeValueCard: some View {
        formCard {
            VStack(spacing: 12) {
                cardRow(icon: "percent") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type")
                            .font(AppFont.labelSmall())
                            .foregroundStyle(AppColors.gray500)
                        HStack(spacing: 8) {
                            ForEach(DiscountCodeType.allCases, id: \.self) { t in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) { type = t }
                                } label: {
                                    Text(t == .percentage ? "Percentage (%)" : "Vast bedrag (SRD)")
                                        .font(AppFont.labelMedium())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity)
                                        .background(type == t ? AppColors.boltGreen : AppColors.gray100)
                                        .foregroundStyle(type == t ? Color.white : AppColors.gray700)
                                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r20))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Divider()
                cardRow(icon: "creditcard.fill") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(type == .percentage ? "Kortingspercentage (%)" : "Kortingsbedrag (SRD)")
                            .font(AppFont.labelSmall())
                            .foregroundStyle(AppColors.gray500)
                        TextField(type == .percentage ? "Bijv. 15" : "Bijv. 25", text: $value)
                            .font(AppFont.bodyMedium())
                            .keyboardType(.decimalPad)
                    }
                }
            }
        }
    }

    private var expiryCard: some View {
        formCard {
            cardRow(icon: "calendar") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vervaldatum")
                        .font(AppFont.labelSmall())
                        .foregroundStyle(AppColors.gray500)
                    DatePicker("", selection: $expiresAt, in: Date()..., displayedComponents: [.date])
                        .labelsHidden()
                        .tint(AppColors.boltGreen)
                }
            }
        }
    }

    private var limitsCard: some View {
        formCard {
            VStack(spacing: 0) {
                cardRow(icon: "number.circle.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $maxUsesEnabled.animation()) {
                            Text("Max. gebruik")
                                .font(AppFont.bodyMedium())
                                .foregroundStyle(AppColors.gray900)
                        }
                        .tint(AppColors.boltGreen)

                        if maxUsesEnabled {
                            TextField("Bijv. 100", text: $maxUsesValue)
                                .font(AppFont.bodyMedium())
                                .keyboardType(.numberPad)
                                .padding(.leading, 4)
                        }
                    }
                }
                Divider().padding(.leading, 52)
                cardRow(icon: "person.fill.checkmark") {
                    Toggle(isOn: $oncePerUser) {
                        Text("Eenmalig per gebruiker")
                            .font(AppFont.bodyMedium())
                            .foregroundStyle(AppColors.gray900)
                    }
                    .tint(AppColors.boltGreen)
                }
                Divider().padding(.leading, 52)
                cardRow(icon: "arrow.up.circle.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $minFareEnabled.animation()) {
                            Text("Minimale ritprijs (SRD)")
                                .font(AppFont.bodyMedium())
                                .foregroundStyle(AppColors.gray900)
                        }
                        .tint(AppColors.boltGreen)
                        if minFareEnabled {
                            TextField("Bijv. 80", text: $minFareValue)
                                .font(AppFont.bodyMedium())
                                .keyboardType(.decimalPad)
                                .padding(.leading, 4)
                        }
                    }
                }
            }
        }
    }

    private var descriptionCard: some View {
        formCard {
            cardRow(icon: "text.alignleft") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Omschrijving (optioneel)")
                        .font(AppFont.labelSmall())
                        .foregroundStyle(AppColors.gray500)
                    TextField("Bijv. Zomercampagne 2026", text: $descriptionText)
                        .font(AppFont.bodyMedium())
                }
            }
        }
    }

    // MARK: - Helpers

    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private func cardRow<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.r8)
                    .fill(AppColors.boltGreenLight)
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.boltGreen)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Save

    private func saveCode() {
        validationError = nil
        let trimmedCode = code.trimmingCharacters(in: .whitespaces)
        guard !trimmedCode.isEmpty else {
            validationError = "Code is verplicht."
            return
        }
        guard let numValue = Double(value.replacingOccurrences(of: ",", with: ".")), numValue > 0 else {
            validationError = "Vul een geldig kortingsbedrag in."
            return
        }
        if type == .percentage, numValue > 100 {
            validationError = "Percentage kan niet groter zijn dan 100."
            return
        }
        var maxUses: Int?
        if maxUsesEnabled {
            guard let parsed = Int(maxUsesValue), parsed > 0 else {
                validationError = "Vul een geldig max. gebruik in."
                return
            }
            maxUses = parsed
        }
        var minFare: Double?
        if minFareEnabled {
            guard let parsed = Double(minFareValue.replacingOccurrences(of: ",", with: ".")), parsed > 0 else {
                validationError = "Vul een geldige minimale ritprijs in."
                return
            }
            minFare = parsed
        }
        let newCode = DiscountCode(
            id: UUID().uuidString,
            code: trimmedCode,
            type: type,
            value: numValue,
            expiresAt: expiresAt,
            isActive: true,
            maxUses: maxUses,
            currentUses: 0,
            oncePerUser: oncePerUser,
            usedByUserIds: [],
            minFare: minFare,
            description: descriptionText.isEmpty ? nil : descriptionText,
            createdAt: Date(),
            createdByAdminId: adminId
        )
        onSave(newCode)
        dismiss()
    }
}
