import Combine
import SwiftUI

// MARK: - ViewModel

@MainActor
final class DriverAvailabilityViewModel: ObservableObject {
    @Published var slots: [String: AvailabilitySlot]
    @Published var isEnabled: Bool
    @Published var isSaving = false
    @Published var showSavedBanner = false

    private static let orderedDays: [String] = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
    ]

    static var dayOrder: [String] { orderedDays }

    init(user: User) {
        var initial = user.weeklyAvailability
        for day in Self.orderedDays where initial[day] == nil {
            initial[day] = AvailabilitySlot()
        }
        self.slots    = initial
        self.isEnabled = user.availabilityEnabled
    }

    func save(authService: AuthService) {
        isSaving = true
        Task {
            await authService.saveAvailability(slots: slots, enabled: isEnabled)
            isSaving = false
            showSavedBanner = true
            try? await Task.sleep(for: .seconds(2))
            showSavedBanner = false
        }
    }

    func startTimeBinding(for day: String) -> Binding<Date> {
        Binding(
            get: { self.slots[day].map { Self.date(from: $0.startTime) } ?? Self.date(from: "08:00") },
            set: { self.slots[day]?.startTime = Self.timeString(from: $0) }
        )
    }

    func endTimeBinding(for day: String) -> Binding<Date> {
        Binding(
            get: { self.slots[day].map { Self.date(from: $0.endTime) } ?? Self.date(from: "17:00") },
            set: { self.slots[day]?.endTime = Self.timeString(from: $0) }
        )
    }

    private static func date(from hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour   = parts.count > 0 ? parts[0] : 8
        comps.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    private static func timeString(from date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }
}

// MARK: - View

struct DriverAvailabilityView: View {
    @StateObject private var viewModel: DriverAvailabilityViewModel
    @EnvironmentObject private var authService: AuthService

    init(user: User) {
        _viewModel = StateObject(wrappedValue: DriverAvailabilityViewModel(user: user))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                masterToggleCard
                if viewModel.isEnabled {
                    dayScheduleCard
                }
                saveButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle(String(localized: "driver.availability.title"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if viewModel.showSavedBanner {
                savedBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showSavedBanner)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isEnabled)
    }

    // MARK: Master toggle

    private var masterToggleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.boltGreenLight)
                        .frame(width: 40, height: 40)
                    Image(systemName: "clock.badge.checkmark.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(AppColors.boltGreen)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("driver.availability.master_toggle")
                        .font(AppFont.bodyMedium())
                        .foregroundStyle(AppColors.gray900)
                    Text("driver.availability.master_subtitle")
                        .font(AppFont.labelSmall())
                        .foregroundStyle(AppColors.gray500)
                }
                Spacer()
                Toggle("", isOn: $viewModel.isEnabled)
                    .tint(AppColors.boltGreen)
                    .labelsHidden()
            }
            .padding(16)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    // MARK: Day schedule

    private var dayScheduleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("driver.availability.schedule_header")
                .font(AppFont.labelMedium())
                .foregroundStyle(AppColors.gray500)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(DriverAvailabilityViewModel.dayOrder.enumerated()), id: \.offset) { index, day in
                    DayRow(
                        day: day,
                        slot: slotBinding(for: day),
                        startTime: viewModel.startTimeBinding(for: day),
                        endTime: viewModel.endTimeBinding(for: day)
                    )
                    if index < DriverAvailabilityViewModel.dayOrder.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
    }

    private func slotBinding(for day: String) -> Binding<AvailabilitySlot> {
        Binding(
            get: { viewModel.slots[day] ?? AvailabilitySlot() },
            set: { viewModel.slots[day] = $0 }
        )
    }

    // MARK: Save button

    private var saveButton: some View {
        Button {
            viewModel.save(authService: authService)
        } label: {
            HStack(spacing: 8) {
                if viewModel.isSaving {
                    ProgressView().tint(.white)
                }
                Text("driver.availability.save")
                    .font(AppFont.labelLarge())
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(viewModel.isSaving ? AppColors.boltGreen.opacity(0.6) : AppColors.boltGreen)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSaving)
    }

    // MARK: Saved banner

    private var savedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
            Text("driver.availability.saved")
                .font(AppFont.labelMedium()).foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(AppColors.boltGreen)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
    }
}

// MARK: - Day Row

private struct DayRow: View {
    let day: String
    @Binding var slot: AvailabilitySlot
    var startTime: Binding<Date>
    var endTime: Binding<Date>

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Toggle("", isOn: $slot.isEnabled)
                    .tint(AppColors.boltGreen)
                    .labelsHidden()
                    .frame(width: 44)
                Text(LocalizedStringKey("driver.availability.day.\(day)"))
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(slot.isEnabled ? AppColors.gray900 : AppColors.gray300)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if slot.isEnabled {
                HStack(spacing: 0) {
                    Spacer().frame(width: 58)
                    timeField(label: "driver.availability.start", binding: startTime)
                    Text("–")
                        .font(AppFont.labelMedium())
                        .foregroundStyle(AppColors.gray500)
                        .padding(.horizontal, 8)
                    timeField(label: "driver.availability.end", binding: endTime)
                    Spacer()
                }
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: slot.isEnabled)
    }

    private func timeField(label: LocalizedStringKey, binding: Binding<Date>) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(AppFont.labelSmall())
                .foregroundStyle(AppColors.gray500)
            DatePicker("", selection: binding, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(AppColors.boltGreen)
        }
    }
}

#Preview {
    NavigationStack {
        DriverAvailabilityView(user: User(
            id: "preview",
            role: .driver,
            weeklyAvailability: [
                "monday":    AvailabilitySlot(isEnabled: true,  startTime: "08:00", endTime: "17:00"),
                "wednesday": AvailabilitySlot(isEnabled: true,  startTime: "09:00", endTime: "20:00"),
                "friday":    AvailabilitySlot(isEnabled: true,  startTime: "07:00", endTime: "15:00"),
            ],
            availabilityEnabled: true
        ))
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
    }
}
