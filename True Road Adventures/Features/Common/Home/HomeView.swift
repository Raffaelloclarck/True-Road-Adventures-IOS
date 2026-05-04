import SwiftUI
import Combine

final class HomeViewModel: ObservableObject {
    @Published var statusMessage: String = "Gereed"

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    func loginDemo() {
        Task {
            do {
                try await container.authService.demoLogin()
                await MainActor.run {
                    statusMessage = "Ingelogd"
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Login mislukt: \(error.localizedDescription)"
                }
            }
        }
    }

    func requestPush() {
        Task {
            let granted = await container.pushService.requestAuthorization()
            await MainActor.run {
                statusMessage = granted ? "Push toegestaan" : "Push geweigerd"
            }
        }
    }

    func requestLocation() {
        container.locationService.requestPermission()
        statusMessage = "Locatie permissie aangevraagd"
    }

    func payDemo() {
        Task {
            do {
                try await container.paymentService.presentPaymentSheet()
                await MainActor.run {
                    statusMessage = "Payment gesimuleerd (configureer echte SDK)"
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Payment mislukt: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var locationService: LocationService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("True Road Adventures")
                    .font(.largeTitle.weight(.bold))

                GroupBox(label: Label("Status", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.statusMessage)
                        if let session = authService.state.session {
                            Text("User ID: \(session.userId)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("Locatie: \(locationService.authorizationDescription)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                LabelledButton(title: "Demo login", icon: "person.crop.circle.fill") {
                    viewModel.loginDemo()
                }

                LabelledButton(title: "Vraag push toestemming", icon: "bell.badge.fill") {
                    viewModel.requestPush()
                }

                LabelledButton(title: "Vraag locatie toestemming", icon: "location.fill") {
                    viewModel.requestLocation()
                }

                LabelledButton(title: "Toon voorbeeld betaling", icon: "creditcard.fill") {
                    viewModel.payDemo()
                }
            }
            .padding()
        }
        .navigationTitle("Home")
    }
}

struct LabelledButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }
}

#Preview {
    HomeView(viewModel: HomeViewModel(container: AppContainer()))
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
        .environmentObject(PushService())
        .environmentObject(LocationService())
}
