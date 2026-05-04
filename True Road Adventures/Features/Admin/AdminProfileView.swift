import SwiftUI

struct AdminProfileView: View {
    let currentUser: User
    @EnvironmentObject private var authService: AuthService
    @State private var showLogoutAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    profileHeader
                    infoSection
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                    logoutSection
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                }
            }
            .background(AppColors.backgroundLight)
            .navigationBarHidden(true)
        }
        .alert(Text("drawer.menu.logout"), isPresented: $showLogoutAlert) {
            Button(role: .cancel) {} label: { Text("rider.profile.delete.cancel") }
            Button(role: .destructive) { authService.logout() } label: { Text("drawer.menu.logout") }
        } message: {
            Text("rider.profile.delete.cancel")
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
                .frame(height: 180)

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 80, height: 80)
                    Image(systemName: "shield.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 2) {
                    Text(currentUser.displayName ?? String(localized: "admin.profile.title"))
                        .font(AppFont.titleLarge())
                        .foregroundStyle(.white)
                    if let email = currentUser.email {
                        Text(email)
                            .font(AppFont.bodySmall())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Text("admin.profile.title")
                        .font(AppFont.labelSmall())
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 2)
                }
                .padding(.bottom, 20)
            }
        }
    }

    private var infoSection: some View {
        VStack(spacing: 1) {
            if let email = currentUser.email {
                infoRow(icon: "envelope.fill", title: "Email", value: email)
            }
            if let phone = currentUser.phoneNumber {
                infoRow(icon: "phone.fill", title: "Telefoon", value: phone)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(AppColors.boltGreen)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.gray500)
                Text(value)
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(AppColors.gray900)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white)
    }

    private var logoutSection: some View {
        Button {
            showLogoutAlert = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.errorRed)
                    .frame(width: 24)
                Text("drawer.menu.logout")
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(AppColors.errorRed)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AdminProfileView(
        currentUser: User(id: "admin1", email: "admin@true-road.app", displayName: "Admin", role: .admin)
    )
    .environmentObject(AuthService(repository: InMemoryAuthRepository()))
}
