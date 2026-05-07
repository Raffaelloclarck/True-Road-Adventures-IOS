import SwiftUI

/// Read-only week availability for admin (same day keys as `DriverAvailabilityView`).
struct AdminDriverScheduleDetailView: View {
    let driver: User

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if driver.availabilityEnabled {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("driver.availability.schedule_header")
                            .font(AppFont.labelMedium())
                            .foregroundStyle(AppColors.gray500)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(Array(DriverAvailabilityViewModel.dayOrder.enumerated()), id: \.offset) { index, day in
                                readOnlyDayRow(day: day, slot: driver.weeklyAvailability[day] ?? AvailabilitySlot())
                                if index < DriverAvailabilityViewModel.dayOrder.count - 1 {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
                        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                    }
                } else {
                    Text("admin.drivers.schedule.disabled")
                        .font(AppFont.bodyMedium())
                        .foregroundStyle(AppColors.gray500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
                        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle(String(localized: "admin.drivers.schedule.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func readOnlyDayRow(day: String, slot: AvailabilitySlot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: slot.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(slot.isEnabled ? AppColors.boltGreen : AppColors.gray300)
                    .frame(width: 44)
                Text(LocalizedStringKey("driver.availability.day.\(day)"))
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(slot.isEnabled ? AppColors.gray900 : AppColors.gray300)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if slot.isEnabled {
                HStack(spacing: 8) {
                    Spacer().frame(width: 58)
                    Text("driver.availability.start")
                        .font(AppFont.labelSmall())
                        .foregroundStyle(AppColors.gray500)
                    Text(slot.startTime)
                        .font(AppFont.labelMedium())
                        .foregroundStyle(AppColors.gray900)
                    Text("–")
                        .font(AppFont.labelMedium())
                        .foregroundStyle(AppColors.gray500)
                    Text("driver.availability.end")
                        .font(AppFont.labelSmall())
                        .foregroundStyle(AppColors.gray500)
                    Text(slot.endTime)
                        .font(AppFont.labelMedium())
                        .foregroundStyle(AppColors.gray900)
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AdminDriverScheduleDetailView(driver: User(
            id: "d1",
            email: "driver@test.com",
            displayName: "Preview Driver",
            role: .driver,
            isDriverOnline: true,
            isApproved: true,
            weeklyAvailability: [
                "monday": AvailabilitySlot(isEnabled: true, startTime: "08:00", endTime: "17:00"),
                "tuesday": AvailabilitySlot(isEnabled: false, startTime: "08:00", endTime: "17:00"),
            ],
            availabilityEnabled: true
        ))
    }
}
