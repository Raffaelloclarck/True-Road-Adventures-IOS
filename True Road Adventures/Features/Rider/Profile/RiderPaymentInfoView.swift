import SwiftUI

struct RiderPaymentInfoView: View {
    @EnvironmentObject private var paymentService: PaymentService

    @State private var isAddingPayment = false
    @State private var isLoadingMethods = false
    @State private var paymentError: String?
    @State private var savedMethods: [SavedPaymentMethod] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isLoadingMethods {
                    ProgressView()
                        .padding(.top, 24)
                } else if !savedMethods.isEmpty {
                    savedMethodsCard
                } else {
                    emptyMethodsCard
                }
                historyCard
                addMethodButton
            }
            .padding(16)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle("payment.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMethods() }
        .alert("payment.error", isPresented: Binding(get: { paymentError != nil }, set: { if !$0 { paymentError = nil } })) {
            Button("payment.ok") { paymentError = nil }
        } message: {
            Text(paymentError ?? "")
        }
    }

    private var savedMethodsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "creditcard.fill").foregroundStyle(AppColors.boltGreen)
                Text("payment.section.methods").font(AppFont.titleSmall()).foregroundStyle(AppColors.gray900)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            ForEach(savedMethods) { method in
                HStack(spacing: 12) {
                    Image(systemName: "creditcard")
                        .frame(width: 24)
                        .foregroundStyle(AppColors.boltGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(method.displayLabel)
                            .font(AppFont.bodyMedium())
                            .foregroundStyle(AppColors.gray700)
                        Text(method.expiryLabel)
                            .font(AppFont.labelSmall())
                            .foregroundStyle(AppColors.gray500)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                if method.id != savedMethods.last?.id { Divider().padding(.leading, 16) }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private var emptyMethodsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "creditcard")
                .font(.system(size: 28))
                .foregroundStyle(AppColors.gray300)
            Text("payment.methods.empty")
                .font(AppFont.bodyMedium())
                .foregroundStyle(AppColors.gray500)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "clock.fill").foregroundStyle(AppColors.boltGreen)
                Text("payment.section.history").font(AppFont.titleSmall()).foregroundStyle(AppColors.gray900)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            HStack {
                Text("payment.history.all")
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
        TRASecondaryButton(title: "payment.add", isDisabled: isAddingPayment, icon: "plus") {
            addPaymentMethod()
        }
    }

    private func loadMethods() async {
        isLoadingMethods = true
        defer { isLoadingMethods = false }
        do {
            savedMethods = try await paymentService.fetchSavedMethods()
        } catch {
            paymentError = error.localizedDescription
        }
    }

    private func addPaymentMethod() {
        isAddingPayment = true
        Task {
            do {
                try await paymentService.addPaymentMethod()
                await loadMethods()
            } catch {
                await MainActor.run { paymentError = error.localizedDescription }
            }
            await MainActor.run { isAddingPayment = false }
        }
    }
}

#Preview {
    NavigationStack {
        RiderPaymentInfoView()
            .environmentObject(PaymentService(config: AppConfig.load()))
    }
}
