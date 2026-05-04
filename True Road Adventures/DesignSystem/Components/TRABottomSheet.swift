import SwiftUI

struct TRABottomSheet<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            content()
        }
        .background(Color.white)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: AppRadius.r24,
                topTrailingRadius: AppRadius.r24
            )
        )
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: -4)
    }

    private var dragHandle: some View {
        Capsule()
            .fill(AppColors.gray300)
            .frame(width: 36, height: 4)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }
}

extension View {
    func traBottomSheet() -> some View {
        self
            .background(Color.white)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: AppRadius.r24,
                    topTrailingRadius: AppRadius.r24
                )
            )
            .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: -4)
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        AppColors.boltGreen.ignoresSafeArea()
        TRABottomSheet {
            VStack(spacing: 16) {
                Text("Bottom Sheet Content")
                    .font(AppFont.titleMedium())
                    .padding()
            }
        }
    }
}
