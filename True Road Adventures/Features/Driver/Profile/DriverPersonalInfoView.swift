import SwiftUI
import PhotosUI

struct DriverPersonalInfoView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var isSaving = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var avatarImage: Image?
    @State private var isUploadingPhoto = false
    @State private var photoUploadError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                avatarSection
                VStack(spacing: 12) {
                    TRATextField(placeholder: "driver.personal.name.placeholder", text: $name, icon: "person")
                    TRATextField(placeholder: "driver.personal.email.placeholder", text: $email,
                                 keyboardType: .emailAddress, icon: "envelope")
                    TRATextField(placeholder: "driver.personal.phone.placeholder", text: $phone,
                                 keyboardType: .phonePad, icon: "phone")
                }
                if let error = authService.state.error {
                    Text(error)
                        .font(AppFont.bodySmall())
                        .foregroundStyle(AppColors.errorRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                TRAPrimaryButton(title: "driver.personal.save", isLoading: isSaving) { save() }
                NavigationLink {
                    DriverPasswordResetView()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.rotation")
                        Text("driver.personal.password.cta")
                    }
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(AppColors.boltGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColors.boltGreen.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle(Text("driver.personal.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = authService.state.user?.displayName ?? ""
            email = authService.state.user?.email ?? ""
            phone = authService.state.user?.phoneNumber ?? ""
        }
        .onChange(of: selectedPhotoItem) { _, item in
            Task { await loadPhoto(from: item) }
        }
    }

    private var avatarSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(AppColors.boltGreenDeep.opacity(0.15)).frame(width: 88, height: 88)
                if let avatarImage {
                    avatarImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())
                } else if let photoURL = authService.state.user?.photoURL {
                    AsyncImage(url: photoURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .frame(width: 88, height: 88).clipShape(Circle())
                        default:
                            Text(String(name.prefix(1)))
                                .font(AppFont.headlineMedium())
                                .foregroundStyle(AppColors.boltGreenDeep)
                        }
                    }
                } else {
                    Text(String(name.prefix(1)))
                        .font(AppFont.headlineMedium())
                        .foregroundStyle(AppColors.boltGreenDeep)
                }

                if isUploadingPhoto {
                    Circle()
                        .fill(.black.opacity(0.4))
                        .frame(width: 88, height: 88)
                    ProgressView()
                        .tint(.white)
                }
            }
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Text("driver.personal.change_photo")
                    .font(AppFont.labelMedium())
                    .foregroundStyle(AppColors.boltGreen)
            }

            if let photoUploadError {
                Text(photoUploadError)
                    .font(AppFont.bodySmall())
                    .foregroundStyle(AppColors.errorRed)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            await authService.updateProfile(displayName: name, phoneNumber: phone)
            await MainActor.run { isSaving = false; dismiss() }
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let compressed = uiImage.jpegData(compressionQuality: 0.75) else { return }
        await MainActor.run {
            avatarImage = Image(uiImage: uiImage)
            isUploadingPhoto = true
            photoUploadError = nil
        }
        do {
            try await authService.uploadProfilePhoto(compressed)
        } catch {
            await MainActor.run {
                avatarImage = nil
                photoUploadError = error.localizedDescription
            }
        }
        await MainActor.run { isUploadingPhoto = false }
    }
}

struct DriverPasswordResetView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var didSucceed = false

    private var isValid: Bool {
        !currentPassword.isEmpty && newPassword == confirmPassword && newPassword.count >= 6
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    TRATextField(placeholder: "driver.personal.password.current", text: $currentPassword,
                                 isSecure: true, icon: "lock")
                    TRATextField(placeholder: "driver.personal.password.new", text: $newPassword,
                                 isSecure: true, icon: "lock.fill")
                    TRATextField(placeholder: "driver.personal.password.confirm", text: $confirmPassword,
                                 isSecure: true, icon: "checkmark.circle")
                }
                if let error = authService.state.error {
                    Text(error)
                        .font(AppFont.bodySmall())
                        .foregroundStyle(AppColors.errorRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if didSucceed {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.successGreen)
                        Text("driver.personal.password.success")
                            .font(AppFont.bodySmall())
                            .foregroundStyle(AppColors.successGreen)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                TRAPrimaryButton(
                    title: "driver.personal.password.title",
                    isLoading: isSaving,
                    isDisabled: !isValid
                ) { save() }
            }
            .padding(24)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle(Text("driver.personal.password.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        isSaving = true
        didSucceed = false
        Task {
            await authService.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            await MainActor.run {
                isSaving = false
                if authService.state.error == nil {
                    didSucceed = true
                    currentPassword = ""
                    newPassword = ""
                    confirmPassword = ""
                }
            }
        }
    }
}

struct DriverVehicleView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var make = ""
    @State private var model = ""
    @State private var year = ""
    @State private var plate = ""
    @State private var isSaving = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                vehicleIcon
                VStack(spacing: 12) {
                    TRATextField(placeholder: "driver.vehicle.brand.placeholder", text: $make, icon: "car")
                    TRATextField(placeholder: "driver.vehicle.model.placeholder", text: $model, icon: "car.fill")
                    TRATextField(placeholder: "driver.vehicle.year.placeholder", text: $year, keyboardType: .numberPad, icon: "calendar")
                    TRATextField(placeholder: "driver.vehicle.plate.placeholder", text: $plate, icon: "doc.text")
                }
                if let error = authService.state.error {
                    Text(error)
                        .font(AppFont.bodySmall())
                        .foregroundStyle(AppColors.errorRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                TRAPrimaryButton(title: "driver.vehicle.save", isLoading: isSaving) { save() }
            }
            .padding(24)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle(Text("driver.vehicle.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadFromUser() }
    }

    private var vehicleIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.r20)
                .fill(AppColors.boltGreenLight)
                .frame(width: 88, height: 88)
            Image(systemName: "car.fill").font(.system(size: 36))
                .foregroundStyle(AppColors.boltGreen)
        }
    }

    private func loadFromUser() {
        let vehicle = authService.state.user?.vehicle
        plate = vehicle?.licensePlate ?? ""
        guard var remaining = vehicle?.vehicleType, !remaining.isEmpty else { return }
        if remaining.hasSuffix(")"), let openParen = remaining.lastIndex(of: "(") {
            let yearStart = remaining.index(after: openParen)
            let yearEnd = remaining.index(before: remaining.endIndex)
            year = String(remaining[yearStart..<yearEnd])
            remaining = String(remaining[..<openParen]).trimmingCharacters(in: .whitespaces)
        }
        let parts = remaining.split(separator: " ", maxSplits: 1)
        make = parts.first.map(String.init) ?? ""
        model = parts.dropFirst().first.map(String.init) ?? ""
    }

    private func save() {
        isSaving = true
        Task {
            let vehicleType = [make, model, year.isEmpty ? "" : "(\(year))"]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            await authService.updateVehicleInfo(vehicleType: vehicleType, licensePlate: plate)
            await MainActor.run { isSaving = false; dismiss() }
        }
    }
}

private enum DocStatus {
    case verified, required, uploading
}

private struct DocumentItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    var status: DocStatus
    var uploadError: String?
}

struct DriverDocumentsView: View {
    @State private var documents: [DocumentItem] = [
        DocumentItem(id: "rijbewijs",          icon: "doc.fill", title: String(localized: "driver.documents.license"),         status: .verified),
        DocumentItem(id: "kentekenbewijs",      icon: "doc.fill", title: String(localized: "driver.documents.registration"),   status: .verified),
        DocumentItem(id: "verzekeringsbewijs",  icon: "doc.fill", title: String(localized: "driver.documents.insurance"),      status: .required),
    ]
    @State private var selectedDocumentId: String?
    @State private var showFilePicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(documents) { doc in
                    docRow(doc)
                }
            }
            .padding(16)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle(Text("driver.documents.title"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            guard let docId = selectedDocumentId else { return }
            Task { await handleFileSelection(result, for: docId) }
        }
    }

    private func docRow(_ item: DocumentItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(AppColors.boltGreenLight).frame(width: 44, height: 44)
                Image(systemName: item.icon).foregroundStyle(AppColors.boltGreen)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(AppFont.titleSmall()).foregroundStyle(AppColors.gray900)
                docStatusLabel(item.status)
                if let error = item.uploadError {
                    Text(error).font(AppFont.labelSmall()).foregroundStyle(AppColors.errorRed)
                }
            }
            Spacer()
            docTrailingView(item)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    @ViewBuilder
    private func docStatusLabel(_ status: DocStatus) -> some View {
        switch status {
        case .verified:
            Text("driver.documents.verified").font(AppFont.bodySmall()).foregroundStyle(AppColors.successGreen)
        case .required:
            Text("driver.documents.upload_required").font(AppFont.bodySmall()).foregroundStyle(AppColors.warningAmber)
        case .uploading:
            Text("driver.documents.uploading").font(AppFont.bodySmall()).foregroundStyle(AppColors.boltGreen)
        }
    }

    @ViewBuilder
    private func docTrailingView(_ item: DocumentItem) -> some View {
        switch item.status {
        case .verified:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(AppColors.successGreen)
        case .uploading:
            ProgressView().tint(AppColors.boltGreen)
        case .required:
            Button {
                selectedDocumentId = item.id
                showFilePicker = true
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColors.warningAmber)
            }
            .buttonStyle(.plain)
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>, for docId: String) async {
        guard let idx = documents.firstIndex(where: { $0.id == docId }) else { return }
        switch result {
        case .failure(let error):
            await MainActor.run { documents[idx].uploadError = error.localizedDescription }
        case .success(let urls):
            guard let url = urls.first else { return }
            await MainActor.run {
                documents[idx].status = .uploading
                documents[idx].uploadError = nil
            }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                _ = data
                try await Task.sleep(nanoseconds: 900_000_000)
                await MainActor.run { documents[idx].status = .verified }
            } catch {
                await MainActor.run {
                    documents[idx].status = .required
                    documents[idx].uploadError = String(localized: "driver.documents.upload_failed") + ": \(error.localizedDescription)"
                }
            }
        }
    }
}

struct DriverEarningsView: View {
    @EnvironmentObject private var rideService: RideService

    private var completedRides: [Ride] {
        rideService.driverHistory.filter { $0.status == .completed }
    }

    private var monthlyEarnings: Double {
        let now = Date()
        let startOfMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now)) ?? now
        return completedRides
            .filter { ($0.endTime ?? $0.updatedAt) >= startOfMonth }
            .reduce(0) { $0 + ($1.totalFareFinal ?? $1.totalFareRealtime) }
    }

    private var monthlyRideCount: Int {
        let now = Date()
        let startOfMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now)) ?? now
        return completedRides.filter { ($0.endTime ?? $0.updatedAt) >= startOfMonth }.count
    }

    private var weeklyEarnings: Double {
        let now = Date()
        let startOfWeek = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        return completedRides
            .filter { ($0.endTime ?? $0.updatedAt) >= startOfWeek }
            .reduce(0) { $0 + ($1.totalFareFinal ?? $1.totalFareRealtime) }
    }

    private var lastWeekEarnings: Double {
        let now = Date()
        let cal = Calendar.current
        let startOfThisWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let startOfLastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: startOfThisWeek) ?? now
        return completedRides
            .filter {
                let date = $0.endTime ?? $0.updatedAt
                return date >= startOfLastWeek && date < startOfThisWeek
            }
            .reduce(0) { $0 + ($1.totalFareFinal ?? $1.totalFareRealtime) }
    }

    private var lastMonthEarnings: Double {
        let now = Date()
        let cal = Calendar.current
        let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let startOfLastMonth = cal.date(byAdding: .month, value: -1, to: startOfThisMonth) ?? now
        return completedRides
            .filter {
                let date = $0.endTime ?? $0.updatedAt
                return date >= startOfLastMonth && date < startOfThisMonth
            }
            .reduce(0) { $0 + ($1.totalFareFinal ?? $1.totalFareRealtime) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                earningsSummaryCard
                earningsPeriodSection
            }
            .padding(16)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle(Text("driver.earnings.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var earningsSummaryCard: some View {
        VStack(spacing: 8) {
            Text("driver.earnings.this_month")
                .font(AppFont.labelMedium()).foregroundStyle(AppColors.gray500)
            Text(String(format: "SRD %.2f", monthlyEarnings))
                .font(AppFont.headlineMedium()).foregroundStyle(AppColors.boltGreen)
            Text(String(format: String(localized: "driver.earnings.rides_completed"), monthlyRideCount))
                .font(AppFont.bodySmall()).foregroundStyle(AppColors.gray500)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private var earningsPeriodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("driver.earnings.section.overview").font(AppFont.titleSmall()).foregroundStyle(AppColors.gray900)
            periodRow(label: "driver.earnings.period.this_week", amount: weeklyEarnings)
            periodRow(label: "driver.earnings.period.last_week", amount: lastWeekEarnings)
            periodRow(label: "driver.earnings.period.last_month", amount: lastMonthEarnings)
        }
    }

    private func periodRow(label: LocalizedStringKey, amount: Double) -> some View {
        HStack {
            Text(label).font(AppFont.bodyMedium()).foregroundStyle(AppColors.gray700)
            Spacer()
            Text(String(format: "SRD %.2f", amount))
                .font(AppFont.bodyMedium()).foregroundStyle(AppColors.gray900)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r12))
    }
}

#Preview { NavigationStack { DriverPersonalInfoView() }.environmentObject(AuthService(repository: InMemoryAuthRepository())) }
