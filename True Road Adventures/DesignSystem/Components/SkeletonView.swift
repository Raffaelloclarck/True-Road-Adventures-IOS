import SwiftUI

struct SkeletonRow: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(shimmerGradient)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(shimmerGradient)
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)

                RoundedRectangle(cornerRadius: 6)
                    .fill(shimmerGradient)
                    .frame(height: 12)
                    .frame(maxWidth: 120)
            }
        }
        .frame(height: 88)
        .padding(.horizontal, 16)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: AppColors.gray100, location: 0),
                .init(color: AppColors.gray300.opacity(0.5), location: 0.4 + phase * 0.2),
                .init(color: AppColors.gray100, location: 0.8),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct SkeletonListPlaceholder: View {
    var count: Int = 4

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonRow()
                Divider()
                    .padding(.horizontal, 16)
            }
        }
    }
}

#Preview {
    SkeletonListPlaceholder()
        .padding(.vertical)
}
