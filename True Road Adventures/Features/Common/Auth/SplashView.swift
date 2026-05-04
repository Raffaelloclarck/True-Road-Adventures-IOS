import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    var onFinished: () -> Void

    var body: some View {
        ZStack {
            AppColors.boltGreen.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Text("True Road")
                            .font(AppFont.displaySmall())
                            .foregroundStyle(.white)
                        Text(" Adventures")
                            .font(AppFont.displaySmall())
                            .foregroundStyle(AppColors.boltGreenDeep)
                    }

                    Text("splash.tagline.rider")
                        .font(AppFont.bodyLarge())
                        .foregroundStyle(.white.opacity(0.85))                }
                .scaleEffect(scale)
                .opacity(opacity)

                Spacer()

                Text("splash.made_in")
                    .font(AppFont.labelMedium())
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 40)
                    .opacity(opacity)
        }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
                scale = 1.0
                opacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onFinished()
            }
        }
    }
}

struct DriverSplashView: View {
    @State private var scale: CGFloat = 0.85
    @State private var opacity: Double = 0
    var onFinished: () -> Void

    var body: some View {
        ZStack {
            AppColors.boltGreenDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 8) {
                    VStack(spacing: 2) {
                        Text("True Road")
                            .font(AppFont.displaySmall())
                            .foregroundStyle(.white)
                        Text("Driver")
                            .font(AppFont.displaySmall())
                            .foregroundStyle(AppColors.boltGreen)
                    }

                    Text("splash.tagline.driver")
                        .font(AppFont.bodyLarge())
                        .foregroundStyle(.white.opacity(0.75))
                }
                .scaleEffect(scale)
                .opacity(opacity)

                Spacer()

                Text("splash.made_in")
                    .font(AppFont.labelMedium())
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 40)
                    .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
                scale = 1.0
                opacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onFinished()
            }
        }
    }
}
