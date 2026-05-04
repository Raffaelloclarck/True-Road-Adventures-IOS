import SwiftUI

struct RiderPaymentInfoView: View {
    @State private var isAddingPayment = false
    @State private var paymentError: String? = nil
    @State private var savedMethods: [PaymentMethod] = PaymentMethod.defaults

    struct PaymentMethod: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
        var isDefault: Bool
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !savedMethods.isEmpty {
                    savedMethodsCard
                }
                historyCard
                addMethodButton
            }
            .padding(16)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle("Betaalinformatie")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Fout", isPresented: Binding(get: { paymentError != nil }, set: { if !$0 { paymentError = nil } })) {
            Button("OK") { paymentError = nil }
        } message: {
            Text(paymentError ?? "")
        }
    }

    private var savedMethodsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "creditcard.fill").foregroundStyle(AppColors.boltGreen)
                Text("Betaalmethoden").font(AppFont.titleSmall()).foregroundStyle(AppColors.gray900)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            ForEach(Array(savedMethods.enumerated()), id: \.element.id) { index, method in
                HStack(spacing: 12) {
                    Image(systemName: method.icon)
                        .frame(width: 24)
                        .foregroundStyle(AppColors.boltGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(method.title)
                            .font(AppFont.bodyMedium())
                            .foregroundStyle(AppColors.gray700)
                        Text(method.subtitle)
                            .font(AppFont.labelSmall())
                            .foregroundStyle(AppColors.gray500)
                    }
                    Spacer()
                    if method.isDefault {
                        Text("Standaard")
                            .font(AppFont.labelSmall())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppColors.boltGreen)
                            .clipShape(Capsule())
                    }
                    Button {
                        savedMethods.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.errorRed)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                if index < savedMethods.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "clock.fill").foregroundStyle(AppColors.boltGreen)
                Text("Betaalgeschiedenis").font(AppFont.titleSmall()).foregroundStyle(AppColors.gray900)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            HStack {
                Text("Bekijk alle transacties")
                    .font(AppFont.bodyMedium()).foregroundStyle(AppColors.gray700)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12)).foregroundStyle(AppColors.gray300)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private var addMethodButton: some View {
        TRASecondaryButton(title: "Betaalmethode toevoegen", isDisabled: isAddingPayment, icon: "plus") {
            addPaymentMethod()
        }
    }

    private func addPaymentMethod() {
        isAddingPayment = true
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                isAddingPayment = false
                let newMethod = PaymentMethod(
                    icon: "creditcard",
                    title: "iDEAL",
                    subtitle: "Koppel je bankrekening",
                    isDefault: savedMethods.isEmpty
                )
                savedMethods.append(newMethod)
            }
        }
    }
}

extension RiderPaymentInfoView.PaymentMethod {
    static let defaults: [RiderPaymentInfoView.PaymentMethod] = [
        .init(icon: "creditcard.fill", title: "•••• 4242", subtitle: "Visa – verloopt 12/27", isDefault: true)
    ]
}

#Preview { NavigationStack { RiderPaymentInfoView() } }
