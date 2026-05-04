import SwiftUI

struct RiderProfileView: View {
    let currentUser: User
    @EnvironmentObject private var authService: AuthService
    @State private var showDeleteAlert = false
    @State private var navigateTo: ProfileDestination? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    profileHeader
                    promoCard
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    profileSections
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }
            }
            .background(AppColors.backgroundLight)
            .navigationBarHidden(true)
            .navigationDestination(item: $navigateTo) { dest in
                profileDestination(dest)
            }
        }
        .alert(Text("rider.profile.delete.title"), isPresented: $showDeleteAlert) {
            Button(role: .cancel) {} label: { Text("rider.profile.delete.cancel") }
            Button(role: .destructive) {
                Task { await authService.deleteAccount() }
            } label: { Text("rider.profile.delete.confirm") }
        } message: {
            Text("rider.profile.delete.body")
        }
    }

    private var profileHeader: some View {
        ZStack(alignment: .bottom) {
            AppColors.boltGreen
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: AppRadius.r32,
                        bottomTrailingRadius: AppRadius.r32
                    )
                )
                .frame(height: 200)

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.3))
                        .frame(width: 80, height: 80)
                    if let url = currentUser.photoURL {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            } else {
                                Text(String(currentUser.displayName?.prefix(1) ?? "U"))
                                    .font(AppFont.displaySmall())
                                    .foregroundStyle(.white)
                            }
                        }
                    } else {
                        Text(String(currentUser.displayName?.prefix(1) ?? "U"))
                            .font(AppFont.displaySmall())
                            .foregroundStyle(.white)
                    }
                }
                VStack(spacing: 4) {
                    Text(currentUser.displayName ?? String(localized: "rider.profile.user.fallback"))
                        .font(AppFont.titleMedium())
                        .foregroundStyle(.white)
                    Text(currentUser.email ?? "")
                        .font(AppFont.bodySmall())
                        .foregroundStyle(.white.opacity(0.8))
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.starYellow)
                        Text("4.9")
                            .font(AppFont.labelSmall())
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var promoCard: some View {
        Button { navigateTo = .promotions } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.boltGreenLight)
                        .frame(width: 44, height: 44)
                    Image(systemName: "gift.fill")
                        .foregroundStyle(AppColors.boltGreen)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("rider.profile.referral.title")
                        .font(AppFont.titleSmall())
                        .foregroundStyle(AppColors.gray900)
                    if currentUser.rideCredits > 0 {
                        Text("SRD \(currentUser.rideCredits, specifier: "%.2f") tegoed beschikbaar")
                            .font(AppFont.bodySmall())
                            .foregroundStyle(AppColors.boltGreen)
                    } else {
                        Text("rider.profile.referral.subtitle")
                            .font(AppFont.bodySmall())
                            .foregroundStyle(AppColors.gray500)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.gray500)
            }
            .padding(16)
            .background(AppColors.boltGreenLight)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        }
        .buttonStyle(.plain)
    }

    private var profileSections: some View {
        VStack(spacing: 16) {
            profileSection(title: "rider.profile.section.account", items: [
                (.personalInfo, "person.fill",         "rider.profile.row.personal"),
                (.payment,      "creditcard.fill",      "rider.profile.row.payment"),
                (.savedPlaces,  "heart.fill",           "rider.profile.row.saved_places"),
                (.preferences,  "slider.horizontal.3",  "rider.profile.row.preferences"),
            ])

            profileSection(title: "rider.profile.section.more", items: [
                (.promotions, "gift.fill",              "rider.profile.row.promotions"),
                (.safety,     "shield.fill",            "rider.profile.row.safety"),
                (.support,    "questionmark.circle.fill", "rider.profile.row.support"),
                (.about,      "info.circle.fill",       "rider.profile.row.about"),
            ])

            deleteButton
        }
    }

    private func profileSection(title: LocalizedStringKey, items: [(ProfileDestination, String, LocalizedStringKey)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppFont.labelMedium())
                .foregroundStyle(AppColors.gray500)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button {
                        navigateTo = item.0
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppColors.boltGreen.opacity(0.1))
                                    .frame(width: 36, height: 36)
                                Image(systemName: item.1)
                                    .font(.system(size: 15))
                                    .foregroundStyle(AppColors.boltGreen)
                            }
                            Text(item.2)
                                .font(AppFont.bodyMedium())
                                .foregroundStyle(AppColors.gray900)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.gray300)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if index < items.count - 1 {
                        Divider().padding(.leading, 66)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        }
    }

    private var deleteButton: some View {
        Button {
            showDeleteAlert = true
        } label: {
            HStack {
                Image(systemName: "trash.fill")
                Text("rider.profile.delete.row")
            }
            .font(AppFont.bodyMedium())
            .foregroundStyle(AppColors.errorRed)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColors.errorRed.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func profileDestination(_ dest: ProfileDestination) -> some View {
        switch dest {
        case .personalInfo:  RiderPersonalInfoView()
        case .payment:       RiderPaymentInfoView()
        case .savedPlaces:   RiderSavedPlacesView()
        case .preferences:   RiderPreferencesView()
        case .promotions:    RiderPromotionsView(currentUser: currentUser)
        case .safety:        RiderSafetyInfoView()
        case .support:       SupportTopicView()
        case .about:         AboutView()
        }
    }
}

enum ProfileDestination: Hashable {
    case personalInfo, payment, savedPlaces, preferences, promotions, safety, support, about
}

#Preview {
    RiderProfileView(
        currentUser: User(id: "demo", email: "demo@test.nl", displayName: "Demo Gebruiker", role: .customer)
    )
    .environmentObject(AuthService(repository: InMemoryAuthRepository()))
}
