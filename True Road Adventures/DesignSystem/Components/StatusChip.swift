import SwiftUI

struct StatusChip: View {
    let label: String
    var outlined: Bool = false
    var color: Color = AppColors.boltGreen

    var body: some View {
        Text(label)
            .font(AppFont.labelSmall())
            .foregroundStyle(outlined ? color : AppColors.boltGreenDeep)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(outlined ? Color.clear : AppColors.boltGreenLight)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r10))
            .overlay(
                outlined
                ? RoundedRectangle(cornerRadius: AppRadius.r10)
                    .strokeBorder(color, lineWidth: 1)
                : nil
            )
    }
}

extension RideStatus {
    var chipLabel: String {
        switch self {
        case .idle:       return "Onbekend"
        case .searching:  return "In afwachting"
        case .accepted:   return "Geaccepteerd"
        case .arrived:    return "Onderweg"
        case .pickedUp:   return "Opgehaald"
        case .completed:  return "Voltooid"
        case .cancelled:  return "Geannuleerd"
        }
    }
    var chipColor: Color {
        switch self {
        case .idle:       return AppColors.gray500
        case .searching:  return AppColors.warningAmber
        case .accepted:   return AppColors.accentBlue
        case .arrived:    return AppColors.boltGreen
        case .pickedUp:   return AppColors.boltGreenDark
        case .completed:  return AppColors.successGreen
        case .cancelled:  return AppColors.errorRed
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        StatusChip(label: "Actief")
        StatusChip(label: "Voltooid", outlined: true)
        StatusChip(label: "Geannuleerd", outlined: true, color: AppColors.errorRed)
    }
    .padding()
}
