import SwiftUI

struct RideStatusIndicator: View {
    let currentStatus: RideStatus

    private let steps: [(RideStatus, String)] = [
        (.searching,  "Chauffeur zoeken"),
        (.accepted,  "Chauffeur op weg"),
        (.arrived,   "Gearriveerd"),
        (.pickedUp,  "Rit gestart"),
        (.completed, "Voltooid"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let isCompleted = stepIndex(step.0) <= stepIndex(currentStatus)
                let isLast = index == steps.count - 1

                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        circle(filled: isCompleted)
                        Text(step.1)
                            .font(AppFont.labelSmall())
                            .foregroundStyle(isCompleted ? AppColors.boltGreenDeep : AppColors.gray500)
                            .multilineTextAlignment(.center)
                            .frame(width: 60)
                    }

                    if !isLast {
                        Rectangle()
                            .fill(isCompleted ? AppColors.boltGreen : AppColors.gray300)
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                            .padding(.top, -10)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func circle(filled: Bool) -> some View {
        Circle()
            .fill(filled ? AppColors.boltGreen : Color.white)
            .frame(width: 20, height: 20)
            .overlay(
                Circle()
                    .strokeBorder(filled ? AppColors.boltGreen : AppColors.gray300, lineWidth: 2)
            )
            .overlay(
                filled
                ? Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                : nil
            )
    }

    private func stepIndex(_ status: RideStatus) -> Int {
        steps.firstIndex(where: { $0.0 == status }) ?? 0
    }
}

#Preview {
    VStack(spacing: 24) {
        RideStatusIndicator(currentStatus: .accepted)
        RideStatusIndicator(currentStatus: .pickedUp)
        RideStatusIndicator(currentStatus: .completed)
    }
    .padding()
}
