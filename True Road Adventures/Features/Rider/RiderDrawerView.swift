import SwiftUI

struct RiderDrawerView: View {
    @EnvironmentObject private var authService: AuthService
    var onNavigate: (RiderDrawerDestination) -> Void
    var onClose: () -> Void

    // Replace with the actual App Store URL once the driver app is published.
    private let driverAppStoreURL = URL(string: "https://apps.apple.com/app/true-road-driver/id0000000000")!

    var body: some View {
        HStack(spacing: 0) {
            drawerContent
                .frame(width: 300)
                .background(Color.white)

            Spacer()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
        }
    }

    private var drawerContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                drawerHeader
                updateBanner
                menuItems
                driverBanner
                Spacer(minLength: 40)
            }
        }
    }

    private var drawerHeader: some View {
        ZStack(alignment: .bottomLeading) {
            AppColors.boltGreen
                .frame(height: 160)

            HStack(spacing: 14) {
                avatarView
                VStack(alignment: .leading, spacing: 2) {
                    Text(authService.state.user?.displayName ?? "Gebruiker")
                        .font(AppFont.titleMedium())
                        .foregroundStyle(.white)
                    Text(authService.state.user?.email ?? "")
                        .font(AppFont.bodySmall())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.3))
                .frame(width: 52, height: 52)
            if let url = authService.state.user?.photoURL {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())
                    } else {
                        Text(String(authService.state.user?.displayName?.prefix(1) ?? "U"))
                            .font(AppFont.headlineSmall())
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Text(String(authService.state.user?.displayName?.prefix(1) ?? "U"))
                    .font(AppFont.headlineSmall())
                    .foregroundStyle(.white)
            }
        }
    }

    private var updateBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(AppColors.boltGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update beschikbaar")
                    .font(AppFont.labelMedium())
                    .foregroundStyle(AppColors.gray900)
                Text("Versie 2.0 is nu beschikbaar")
                    .font(AppFont.bodySmall())
                    .foregroundStyle(AppColors.gray500)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.gray500)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.boltGreenLight)
    }

    private var menuItems: some View {
        VStack(spacing: 0) {
            drawerRow(icon: "house.fill",       label: "Home",          destination: .home)
            drawerRow(icon: "clock.fill",        label: "Mijn ritten",   destination: .rides)
            drawerRow(icon: "heart.fill",        label: "Favorieten",    destination: .savedPlaces)
            drawerRow(icon: "creditcard.fill",   label: "Betaling",      destination: .payment)
            drawerRow(icon: "gift.fill",         label: "Promoties",     destination: .promotions, badge: "NIEUW")
            drawerRow(icon: "shield.fill",       label: "Veiligheid",    destination: .safety)
            drawerRow(icon: "person.fill",       label: "Profiel",       destination: .profile)
            Divider().padding(.horizontal, 16)
            drawerRow(icon: "questionmark.circle.fill", label: "Hulp & Support", destination: .support)
            drawerRow(icon: "info.circle.fill",  label: "Over de app",   destination: .about)
            drawerRow(icon: "arrow.right.circle.fill", label: "Uitloggen", destination: .logout, tint: AppColors.errorRed)
        }
    }

    private func drawerRow(
        icon: String,
        label: String,
        destination: RiderDrawerDestination,
        badge: String? = nil,
        tint: Color = AppColors.boltGreen
    ) -> some View {
        Button {
            onNavigate(destination)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tint.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(tint)
                }

                Text(label)
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(AppColors.gray900)

                Spacer()

                if let badge {
                    Text(badge)
                        .font(AppFont.labelSmall())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.badgeRed)
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.gray300)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var driverBanner: some View {
        Button {
            UIApplication.shared.open(driverAppStoreURL)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .foregroundStyle(AppColors.boltGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Word chauffeur")
                        .font(AppFont.labelMedium())
                        .foregroundStyle(AppColors.gray900)
                    Text("Verdien geld als True Road chauffeur")
                        .font(AppFont.bodySmall())
                        .foregroundStyle(AppColors.gray500)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.gray300)
            }
            .padding(12)
            .background(AppColors.driverBannerMint)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

enum RiderDrawerDestination {
    case home, rides, savedPlaces, payment, promotions, safety, profile, support, about, logout
}

#Preview {
    RiderDrawerView(onNavigate: { _ in }, onClose: {})
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
}
