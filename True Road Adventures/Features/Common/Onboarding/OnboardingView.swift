import SwiftUI

// MARK: - Model

struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
}

extension OnboardingPage {
    static let riderPages: [OnboardingPage] = [
        OnboardingPage(
            icon: "mappin.and.ellipse",
            iconColor: AppColors.boltGreen,
            title: "Boek een rit",
            subtitle: "Voer je bestemming in en vind een chauffeur bij jou in de buurt."
        ),
        OnboardingPage(
            icon: "location.fill.viewfinder",
            iconColor: AppColors.accentBlue,
            title: "Volg je chauffeur",
            subtitle: "Zie je chauffeur realtime op de kaart rijden — altijd op de hoogte."
        ),
        OnboardingPage(
            icon: "creditcard.fill",
            iconColor: AppColors.successGreen,
            title: "Betaal eenvoudig",
            subtitle: "Na je rit wordt automatisch afgerekend. Geen contant geld nodig."
        )
    ]

    static let driverPages: [OnboardingPage] = [
        OnboardingPage(
            icon: "power.circle.fill",
            iconColor: AppColors.boltGreen,
            title: "Ga online",
            subtitle: "Zet jezelf online om ritaanvragen te ontvangen wanneer jij beschikbaar bent."
        ),
        OnboardingPage(
            icon: "bell.badge.fill",
            iconColor: AppColors.warningAmber,
            title: "Accepteer ritten",
            subtitle: "Bekijk de ritdetails en accepteer of weiger binnen de tijd."
        ),
        OnboardingPage(
            icon: "map.fill",
            iconColor: AppColors.accentBlue,
            title: "Navigeer en verdien",
            subtitle: "Volg de ingebouwde navigatie naar de klant en de bestemming."
        )
    ]
}

// MARK: - View

struct OnboardingView: View {
    let pages: [OnboardingPage]
    let onComplete: () -> Void

    @State private var currentPage = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppColors.backgroundLight.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                bottomBar
            }

            skipButton
        }
    }

    // MARK: - Subviews

    private var skipButton: some View {
        Button("Overslaan") {
            onComplete()
        }
        .font(AppFont.labelLarge())
        .foregroundStyle(AppColors.gray500)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var bottomBar: some View {
        VStack(spacing: 24) {
            pageIndicator

            if currentPage < pages.count - 1 {
                TRAPrimaryButton(title: "Volgende") {
                    withAnimation { currentPage += 1 }
                }
            } else {
                TRAPrimaryButton(title: "Aan de slag") {
                    onComplete()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? AppColors.boltGreen : AppColors.gray300)
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: currentPage)
            }
        }
    }
}

// MARK: - Single slide

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.iconColor.opacity(0.12))
                    .frame(width: 140, height: 140)

                Image(systemName: page.icon)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(page.iconColor)
            }

            VStack(spacing: 12) {
                Text(page.title)
                    .font(AppFont.headlineMedium())
                    .foregroundStyle(AppColors.gray900)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(AppFont.bodyLarge())
                    .foregroundStyle(AppColors.gray500)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Previews

#Preview("Rider") {
    OnboardingView(pages: OnboardingPage.riderPages) { }
}

#Preview("Driver") {
    OnboardingView(pages: OnboardingPage.driverPages) { }
}
