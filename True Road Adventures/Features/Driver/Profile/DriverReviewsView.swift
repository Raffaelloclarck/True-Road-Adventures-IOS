import SwiftUI

struct DriverReviewsView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var ratings: [Rating] = []
    @State private var isLoading = true

    private var averageScore: Double {
        guard !ratings.isEmpty else { return 0 }
        return Double(ratings.reduce(0) { $0 + $1.score }) / Double(ratings.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isLoading {
                    SkeletonListPlaceholder(count: 3).padding(.top, 8)
                } else if ratings.isEmpty {
                    EmptyStateView(
                        icon: "star.slash",
                        title: String(localized: "driver.reviews.empty.title"),
                        subtitle: String(localized: "driver.reviews.empty.body")
                    )
                    .padding(.top, 40)
                } else {
                    ratingSummary
                    ForEach(ratings) { rating in
                        reviewCard(rating: rating)
                    }
                }
            }
            .padding(16)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle(String(localized: "driver.reviews.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            ratings = await authService.fetchDriverRatings()
            isLoading = false
        }
    }

    private var ratingSummary: some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                Text(String(format: "%.1f", averageScore))
                    .font(AppFont.displaySmall())
                    .foregroundStyle(AppColors.gray900)
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: "star.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.starYellow)
                    }
                }
                Text(String(format: String(localized: "driver.reviews.count"), ratings.count))
                    .font(AppFont.bodySmall()).foregroundStyle(AppColors.gray500)
            }
            Spacer()
            VStack(spacing: 6) {
                ForEach([5, 4, 3, 2, 1], id: \.self) { star in
                    HStack(spacing: 8) {
                        Text("\(star)").font(AppFont.labelSmall()).foregroundStyle(AppColors.gray500)
                            .frame(width: 10)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(AppColors.gray100)
                                .frame(height: 6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(AppColors.starYellow)
                                        .frame(width: geo.size.width * barFraction(for: star),
                                               height: 6),
                                    alignment: .leading
                                )
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private func barFraction(for star: Int) -> CGFloat {
        guard !ratings.isEmpty else { return 0 }
        let count = ratings.filter { $0.score == star }.count
        return CGFloat(count) / CGFloat(ratings.count)
    }

    private func reviewCard(rating: Rating) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= rating.score ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.starYellow)
                    }
                }
                Spacer()
                Text(rating.createdAt.formatted(.relative(presentation: .named)))
                    .font(AppFont.labelSmall()).foregroundStyle(AppColors.gray500)
            }
            if let comment = rating.comment, !comment.isEmpty {
                Text(comment).font(AppFont.bodyMedium()).foregroundStyle(AppColors.gray700)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }
}

#Preview {
    NavigationStack { DriverReviewsView() }
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
}
