import SwiftUI

enum AdminTab: String {
    case rides, drivers, notifications, profile
}

struct AdminTabView: View {
    let container: AppContainer
    let currentUser: User

    @State private var selectedTab: AdminTab = .rides

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            AdminTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .rides:
            AdminRidesView()
        case .drivers:
            AdminDriversView()
        case .notifications:
            AdminNotificationView()
        case .profile:
            AdminProfileView(currentUser: currentUser)
        }
    }
}

private struct AdminTabBar: View {
    @Binding var selectedTab: AdminTab

    private let tabs: [(tab: AdminTab, icon: String, label: LocalizedStringKey)] = [
        (.rides,         "car.fill",       "admin.tab.rides"),
        (.drivers,       "person.2.fill",  "admin.tab.drivers"),
        (.notifications, "bell.fill",      "admin.tab.notifications"),
        (.profile,       "person.fill",    "admin.tab.profile"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                ForEach(tabs, id: \.tab) { item in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            selectedTab = item.tab
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.icon)
                                .font(.system(size: 22, weight: .semibold))
                            Text(item.label)
                                .font(AppFont.labelSmall())
                        }
                        .foregroundStyle(selectedTab == item.tab ? AppColors.boltGreen : AppColors.gray300)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.white)
            .padding(.bottom, 20)
        }
        .background(Color.white)
    }
}
