import SwiftUI

struct AdminDriversView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var driverToReject: User? = nil

    var body: some View {
        NavigationStack {
            Group {
                if authService.pendingDrivers.isEmpty {
                    VStack {
                        Spacer()
                        EmptyStateView(
                            icon: "person.2.fill",
                            title: String(localized: "admin.drivers.empty"),
                            subtitle: String(localized: "admin.drivers.empty.body")
                        )
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(authService.pendingDrivers) { driver in
                                DriverApprovalCard(
                                    driver: driver,
                                    onApprove: {
                                        Task { await authService.approveDriver(userId: driver.id) }
                                    },
                                    onReject: {
                                        driverToReject = driver
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(AppColors.backgroundLight)
            .navigationTitle(Text("admin.drivers.title"))
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog(
                String(localized: "admin.drivers.reject.confirm"),
                isPresented: Binding(
                    get: { driverToReject != nil },
                    set: { if !$0 { driverToReject = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let driver = driverToReject {
                    Button(String(localized: "admin.drivers.reject"), role: .destructive) {
                        Task { await authService.rejectDriver(userId: driver.id) }
                        driverToReject = nil
                    }
                }
                Button(String(localized: "action.cancel"), role: .cancel) {
                    driverToReject = nil
                }
            }
        }
    }
}

private struct DriverApprovalCard: View {
    let driver: User
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppColors.boltGreen.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "person.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.boltGreen)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(driver.displayName ?? driver.email ?? driver.id)
                        .font(AppFont.titleSmall())
                        .foregroundStyle(AppColors.gray900)

                    if let email = driver.email {
                        Text(email)
                            .font(AppFont.bodySmall())
                            .foregroundStyle(AppColors.gray500)
                    }
                }

                Spacer()

                StatusChip(label: String(localized: "admin.drivers.pending"), outlined: true, color: AppColors.warningAmber)
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    onReject()
                } label: {
                    Text("admin.drivers.reject")
                        .font(AppFont.labelMedium())
                        .foregroundStyle(AppColors.errorRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppColors.errorRed.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r10))
                }
                .buttonStyle(.plain)

                Button {
                    onApprove()
                } label: {
                    Text("admin.drivers.approve")
                        .font(AppFont.labelMedium())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppColors.boltGreen)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    AdminDriversView()
        .environmentObject(AuthService(repository: InMemoryAuthRepository(seedUsers: [
            User(id: "d1", email: "jan@test.com", displayName: "Jan de Vries", role: .driver, isApproved: false),
            User(id: "d2", email: "lisa@test.com", displayName: "Lisa Bakker", role: .driver, isApproved: false),
        ])))
}
