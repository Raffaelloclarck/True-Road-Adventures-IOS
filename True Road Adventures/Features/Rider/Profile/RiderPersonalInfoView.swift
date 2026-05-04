import SwiftUI
import PhotosUI

struct RiderPersonalInfoView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var isSaving = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isUploadingPhoto = false
    @State private var photoUploadError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                avatarSection

                VStack(spacing: 12) {
                    TRATextField(placeholder: "personal_info.name.placeholder", text: $name, icon: "person")
                    TRATextField(placeholder: "personal_info.email.placeholder", text: $email,
                                 keyboardType: .emailAddress, icon: "envelope")
                }

                TRAPrimaryButton(title: "personal_info.save", isLoading: isSaving) {
                    save()
                }
            }
            .padding(24)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle(Text("personal_info.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = authService.state.user?.displayName ?? ""
            email = authService.state.user?.email ?? ""
        }
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                guard let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let compressed = image.jpegData(compressionQuality: 0.75) else { return }
                await MainActor.run {
                    selectedImage = image
                    photoUploadError = nil
                }
                await uploadPhoto(data: compressed)
            }
        }
    }

    private var avatarSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(AppColors.boltGreenLight).frame(width: 88, height: 88)
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())
                } else if let url = authService.state.user?.photoURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        avatarInitials
                    }
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
                } else {
                    avatarInitials
                }

                if isUploadingPhoto {
                    Circle()
                        .fill(.black.opacity(0.4))
                        .frame(width: 88, height: 88)
                    ProgressView()
                        .tint(.white)
                }
            }

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                Text("personal_info.change_photo")
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

    private var avatarInitials: some View {
        Text(String(name.prefix(1)))
            .font(AppFont.headlineMedium())
            .foregroundStyle(AppColors.boltGreen)
    }

    private func uploadPhoto(data: Data) async {
        await MainActor.run { isUploadingPhoto = true }
        do {
            try await authService.uploadProfilePhoto(data)
        } catch {
            await MainActor.run {
                selectedImage = nil
                photoUploadError = error.localizedDescription
            }
        }
        await MainActor.run { isUploadingPhoto = false }
    }

    private func save() {
        isSaving = true
        Task {
            await authService.updateProfile(displayName: name, phoneNumber: "")
            await MainActor.run { isSaving = false; dismiss() }
        }
    }
}

#Preview {
    NavigationStack { RiderPersonalInfoView() }
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
}
