import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AboutView: View {
    private enum AppURL {
        static let terms       = URL(string: "https://www.trueroadadventures.nl/servicevoorwaarden")!
        static let privacy     = URL(string: "https://www.trueroadadventures.nl/privacybeleid")!
        static let website     = URL(string: "https://www.trueroadadventures.nl")!
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                appHeader
                infoSection
                linksSection
            }
            .padding(16)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle(Text("about.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.r20)
                    .fill(AppColors.boltGreen)
                    .frame(width: 88, height: 88)
                Image(systemName: "road.lanes")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text("about.app_name")
                .font(AppFont.titleLarge())
                .foregroundStyle(AppColors.gray900)
            Text("about.version")
                .font(AppFont.bodySmall())
                .foregroundStyle(AppColors.gray500)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private var infoSection: some View {
        VStack(spacing: 0) {
            infoRow(title: "about.developer.title", value: "about.developer.name")
            Divider().padding(.leading, 16)
            infoRow(title: "about.country.title", value: "about.country.name")
            Divider().padding(.leading, 16)
            infoRow(title: "about.license.title", value: "about.license.body")
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private func infoRow(title: LocalizedStringKey, value: LocalizedStringKey) -> some View {
        HStack {
            Text(title).font(AppFont.bodyMedium()).foregroundStyle(AppColors.gray700)
            Spacer()
            Text(value).font(AppFont.bodyMedium()).foregroundStyle(AppColors.gray500)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private var linksSection: some View {
        VStack(spacing: 0) {
            linkRow(title: "about.terms", icon: "doc.text.fill", url: AppURL.terms)
            Divider().padding(.leading, 16)
            linkRow(title: "about.privacy", icon: "shield.fill", url: AppURL.privacy)
            Divider().padding(.leading, 16)
            linkRow(title: "about.website", icon: "globe", url: AppURL.website)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private func linkRow(title: LocalizedStringKey, icon: String, url: URL) -> some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16))
                    .foregroundStyle(AppColors.boltGreen).frame(width: 20)
                Text(title).font(AppFont.bodyMedium()).foregroundStyle(AppColors.gray900)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 12))
                    .foregroundStyle(AppColors.boltGreen)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

#Preview { NavigationStack { AboutView() } }
