import SwiftUI

struct DriverPendingApprovalView: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        ZStack {
            AppColors.backgroundLight.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(AppColors.boltGreen.opacity(0.12))
                            .frame(width: 96, height: 96)
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(AppColors.boltGreen)
                    }

                    VStack(spacing: 8) {
                        Text("driver.pending.title")
                            .font(AppFont.headlineSmall())
                            .foregroundStyle(AppColors.gray900)
                            .multilineTextAlignment(.center)

                        Text("driver.pending.body")
                            .font(AppFont.bodyMedium())
                            .foregroundStyle(AppColors.gray500)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }

                Spacer()

                TRASecondaryButton(title: "drawer.menu.logout") {
                    authService.logout()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}

#Preview {
    DriverPendingApprovalView()
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
}
