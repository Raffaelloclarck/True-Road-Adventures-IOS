import SwiftUI

struct DriverProfileView: View {
    let currentUser: User
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var rideService: RideService
    @State private var showDeleteAlert = false
    @State private var navigateTo: DriverProfileDestination? = nil
    @State private var driverRatings: [Rating] = []

    private var liveUser: User { authService.state.user ?? currentUser }

    private var effectiveCompletedRides: Int {
        let fromHistory = rideService.driverHistory.filter { $0.status == .completed }.count
        return max(fromHistory, liveUser.completedRides)
    }

    private var effectiveRating: Double? {
        guard !driverRatings.isEmpty else { return liveUser.rating }
        return Double(driverRatings.map(\.score).reduce(0, +)) / Double(driverRatings.count)
    }

    private var acceptanceRatio: String {
        let history = rideService.driverHistory
        guard !history.isEmpty else { return "–" }
        let accepted = history.filter { $0.status == .completed }.count
        let total = history.filter { $0.status == .completed || $0.status == .cancelled }.count
        guard total > 0 else { return "–" }
        let pct = Int(Double(accepted) / Double(total) * 100)
        return "\(pct)%"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    profileHeader
                    statsRow.padding(.horizontal, 16).padding(.top, 12)
                    profileSections.padding(.horizontal, 16).padding(.top, 16)
                }
            }
            .background(AppColors.backgroundLight)
            .navigationBarHidden(true)
            .navigationDestination(item: $navigateTo) { dest in
                driverProfileDestination(dest)
            }
            .task {
                driverRatings = await authService.fetchDriverRatings()
            }
        }
        .alert(Text("driver.profile.delete.title"), isPresented: $showDeleteAlert) {
            Button(role: .cancel) {} label: { Text("driver.profile.delete.cancel") }
            Button(role: .destructive) {
                Task { await authService.deleteAccount() }
            } label: { Text("driver.profile.delete.confirm") }
        } message: {
            Text("driver.profile.delete.body")
        }
    }

    private var profileHeader: some View {
        ZStack(alignment: .bottom) {
            AppColors.boltGreenDeep
                .clipShape(UnevenRoundedRectangle(
                    bottomLeadingRadius: AppRadius.r32,
                    bottomTrailingRadius: AppRadius.r32
                ))
                .frame(height: 200)
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(.white.opacity(0.2)).frame(width: 80, height: 80)
                    if let url = liveUser.photoURL {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            } else {
                                Text(String(liveUser.displayName?.prefix(1) ?? "C"))
                                    .font(AppFont.displaySmall()).foregroundStyle(.white)
                            }
                        }
                    } else {
                        Text(String(liveUser.displayName?.prefix(1) ?? "C"))
                            .font(AppFont.displaySmall()).foregroundStyle(.white)
                    }
                }
                VStack(spacing: 4) {
                    Text(liveUser.displayName ?? String(localized: "driver.profile.driver.fallback"))
                        .font(AppFont.titleMedium()).foregroundStyle(.white)
                    Text(liveUser.email ?? "")
                        .font(AppFont.bodySmall()).foregroundStyle(.white.opacity(0.75))
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 11))
                            .foregroundStyle(AppColors.starYellow)
                        if let rating = effectiveRating {
                            Text(String(format: "%.1f", rating))
                                .font(AppFont.labelSmall()).foregroundStyle(.white)
                            Text("·").foregroundStyle(.white.opacity(0.5))
                        }
                        Text("\(effectiveCompletedRides) " + String(localized: "tab.rides").lowercased())
                            .font(AppFont.labelSmall()).foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statItem(value: "\(effectiveCompletedRides)", label: "driver.profile.stat.rides")
            Divider().frame(height: 40)
            statItem(
                value: effectiveRating.map { String(format: "%.1f★", $0) } ?? "–",
                label: "driver.profile.stat.rating"
            )
            Divider().frame(height: 40)
            statItem(value: acceptanceRatio, label: "driver.profile.stat.acceptance")
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private func statItem(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(value).font(AppFont.titleMedium()).foregroundStyle(AppColors.boltGreen)
            Text(label).font(AppFont.labelSmall()).foregroundStyle(AppColors.gray500)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var profileSections: some View {
        VStack(spacing: 16) {
            driverSection(title: "driver.profile.section.account", items: [
                (.personalInfo,  "person.fill",                  "driver.profile.row.personal"),
                (.vehicle,       "car.fill",                     "driver.profile.row.vehicle"),
                (.availability,  "clock.badge.checkmark.fill",   "driver.profile.row.availability"),
                (.documents,     "doc.fill",                     "driver.profile.row.documents"),
            ])
            driverSection(title: "driver.profile.section.activity", items: [
                (.reviews,       "star.fill",          "driver.profile.row.reviews"),
                (.earnings,      "eurosign.circle.fill", "driver.profile.row.earnings"),
            ])
            driverSection(title: "driver.profile.section.more", items: [
                (.support,       "questionmark.circle.fill", "driver.profile.row.support"),
                (.about,         "info.circle.fill",   "driver.profile.row.about"),
            ])
            logoutDeleteButtons
        }
    }

    private func driverSection(title: LocalizedStringKey, items: [(DriverProfileDestination, String, LocalizedStringKey)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(AppFont.labelMedium()).foregroundStyle(AppColors.gray500)
                .padding(.horizontal, 4).padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button { navigateTo = item.0 } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppColors.boltGreen.opacity(0.1))
                                    .frame(width: 36, height: 36)
                                Image(systemName: item.1).font(.system(size: 15))
                                    .foregroundStyle(AppColors.boltGreen)
                            }
                            Text(item.2).font(AppFont.bodyMedium()).foregroundStyle(AppColors.gray900)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12))
                                .foregroundStyle(AppColors.gray300)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    if index < items.count - 1 { Divider().padding(.leading, 66) }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        }
    }

    private var logoutDeleteButtons: some View {
        VStack(spacing: 10) {
            TRASecondaryButton(title: "driver.profile.logout", icon: "arrow.right.circle.fill") {
                authService.logout()
            }
            Button {
                showDeleteAlert = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("driver.profile.delete")
                }
                .font(AppFont.bodyMedium()).foregroundStyle(AppColors.errorRed)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(AppColors.errorRed.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func driverProfileDestination(_ dest: DriverProfileDestination) -> some View {
        switch dest {
        case .personalInfo: DriverPersonalInfoView()
        case .vehicle:      DriverVehicleView()
        case .availability: DriverAvailabilityView(user: liveUser)
        case .documents:    DriverDocumentsView()
        case .reviews:      DriverReviewsView()
        case .earnings:     DriverEarningsView()
        case .support:      SupportTopicView()
        case .about:        AboutView()
        }
    }
}

enum DriverProfileDestination: Hashable {
    case personalInfo, vehicle, availability, documents, reviews, earnings, support, about
}

#Preview {
    DriverProfileView(currentUser: User(id: "d1", email: "driver@test.nl",
                                        displayName: "Jan Chauffeur", role: .driver,
                                        rating: 4.8, completedRides: 142))
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
        .environmentObject(
            RideService(
                repository: InMemoryRideRepository(),
                navigationManager: NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil))
            )
        )
}
