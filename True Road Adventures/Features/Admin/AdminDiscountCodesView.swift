import SwiftUI

struct AdminDiscountCodesView: View {
    let currentUser: User
    @EnvironmentObject private var discountCodeService: DiscountCodeService

    @State private var showCreateSheet = false
    @State private var errorMessage: String?
    @State private var deleteTarget: DiscountCode?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pageHeader
                codesList
            }
            .background(AppColors.backgroundLight)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showCreateSheet) {
            AdminDiscountCodeFormView(adminId: currentUser.id) { code in
                Task {
                    do {
                        try await discountCodeService.createCode(code)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .alert("Fout", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Kortingscode verwijderen?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        ), titleVisibility: .visible) {
            if let target = deleteTarget {
                Button("Verwijderen", role: .destructive) {
                    Task {
                        do { try await discountCodeService.deleteCode(target) } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            Button("Annuleren", role: .cancel) { deleteTarget = nil }
        }
        .onAppear { discountCodeService.startListening() }
        .onDisappear { discountCodeService.stopListening() }
    }

    // MARK: - Header

    private var pageHeader: some View {
        ZStack(alignment: .bottom) {
            AppColors.boltGreen
                .clipShape(UnevenRoundedRectangle(
                    bottomLeadingRadius: AppRadius.r32,
                    bottomTrailingRadius: AppRadius.r32
                ))
                .frame(height: 190)

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 68, height: 68)
                    Image(systemName: "tag.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

                Text("Kortingscodes")
                    .font(AppFont.titleLarge())
                    .foregroundStyle(.white)

                Text("Beheer actieve kortingscodes")
                    .font(AppFont.bodySmall())
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - List

    private var codesList: some View {
        ScrollView {
            VStack(spacing: 0) {
                createButton
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                if discountCodeService.isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if discountCodeService.allCodes.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(discountCodeService.allCodes) { code in
                            DiscountCodeRow(code: code) {
                                Task {
                                    do { try await discountCodeService.toggleActive(code) } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            } onDelete: {
                                deleteTarget = code
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var createButton: some View {
        Button { showCreateSheet = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Nieuwe kortingscode")
                    .font(AppFont.labelLarge())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(AppColors.boltGreen)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
            .shadow(color: AppColors.boltGreen.opacity(0.3), radius: 4, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tag.slash")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.gray300)
            Text("Geen kortingscodes")
                .font(AppFont.titleSmall())
                .foregroundStyle(AppColors.gray500)
            Text("Maak een nieuwe code aan via de knop hierboven.")
                .font(AppFont.bodySmall())
                .foregroundStyle(AppColors.gray400)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .padding(.horizontal, 32)
    }
}

// MARK: - DiscountCodeRow

private struct DiscountCodeRow: View {
    let code: DiscountCode
    let onToggle: () -> Void
    let onDelete: () -> Void

    var statusColor: Color {
        if code.isExpired || code.isMaxUsesReached { return AppColors.errorRed }
        if !code.isActive { return AppColors.gray400 }
        return AppColors.boltGreen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.r8)
                        .fill(AppColors.boltGreenLight)
                        .frame(width: 40, height: 40)
                    Image(systemName: "tag.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.boltGreen)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(code.code)
                            .font(AppFont.titleSmall())
                            .foregroundStyle(AppColors.gray900)
                        statusPill
                    }
                    Text(valueLabel)
                        .font(AppFont.bodySmall())
                        .foregroundStyle(AppColors.gray500)
                    if let desc = code.description {
                        Text(desc)
                            .font(AppFont.labelSmall())
                            .foregroundStyle(AppColors.gray400)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { code.isActive },
                    set: { _ in onToggle() }
                ))
                .tint(AppColors.boltGreen)
                .labelsHidden()
                .disabled(code.isExpired || code.isMaxUsesReached)
            }
            .padding(14)

            Divider().padding(.leading, 66)

            HStack(spacing: 16) {
                infoChip(icon: "calendar", label: expiryLabel)
                infoChip(icon: "person.2", label: usageLabel)
                Spacer()
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.errorRed)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private var statusPill: some View {
        Text(code.statusLabel)
            .font(AppFont.labelSmall())
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.1))
            .clipShape(Capsule())
    }

    private var valueLabel: String {
        switch code.type {
        case .percentage:
            return "\(Int(code.value))% korting"
        case .fixed:
            return String(format: "SRD %.0f korting", code.value)
        }
    }

    private var expiryLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: code.expiresAt)
    }

    private var usageLabel: String {
        if let max = code.maxUses {
            return "\(code.currentUses)/\(max)"
        }
        return "\(code.currentUses) gebruikt"
    }

    private func infoChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.gray400)
            Text(label)
                .font(AppFont.labelSmall())
                .foregroundStyle(AppColors.gray500)
        }
    }
}
