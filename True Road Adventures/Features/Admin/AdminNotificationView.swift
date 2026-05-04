import SwiftUI
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

struct AdminNotificationView: View {
    @State private var title = ""
    @State private var messageBody = ""
    @State private var target: NotificationTarget = .all
    @State private var isSending = false
    @State private var result: SendResult?

    enum NotificationTarget: String, CaseIterable, Identifiable {
        case all, riders, drivers
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .all:     return "admin.notification.target.all"
            case .riders:  return "admin.notification.target.riders"
            case .drivers: return "admin.notification.target.drivers"
            }
        }
        var firestoreValue: String {
            switch self {
            case .all:     return "all"
            case .riders:  return "riders"
            case .drivers: return "drivers"
            }
        }
    }

    struct SendResult: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    pageHeader
                    formSection
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                    sendButton
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                        .padding(.bottom, 32)
                }
            }
            .background(AppColors.backgroundLight)
            .navigationBarHidden(true)
        }
        .alert(
            result?.isError == true ? Text("Fout") : Text("Verzonden"),
            isPresented: Binding(
                get: { result != nil },
                set: { if !$0 { result = nil } }
            )
        ) {
            Button("OK") { result = nil }
        } message: {
            Text(result?.message ?? "")
        }
    }

    private var pageHeader: some View {
        ZStack(alignment: .bottom) {
            AppColors.boltGreen
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: AppRadius.r32,
                        bottomTrailingRadius: AppRadius.r32
                    )
                )
                .frame(height: 140)

            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 60, height: 60)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("admin.notification.title")
                    .font(AppFont.titleLarge())
                    .foregroundStyle(.white)
                    .padding(.bottom, 20)
            }
        }
    }

    private var formSection: some View {
        VStack(spacing: 1) {
            fieldRow(label: "admin.notification.field.title") {
                TextField("admin.notification.field.title.placeholder", text: $title)
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(AppColors.gray900)
            }

            Divider()
                .padding(.leading, 56)

            fieldRow(label: "admin.notification.field.body", alignTop: true) {
                TextField(
                    "admin.notification.field.body.placeholder",
                    text: $messageBody,
                    axis: .vertical
                )
                .lineLimit(4, reservesSpace: true)
                .font(AppFont.bodyMedium())
                .foregroundStyle(AppColors.gray900)
            }

            Divider()
                .padding(.leading, 56)

            HStack(spacing: 14) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.boltGreen)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Text("admin.notification.field.target")
                        .font(AppFont.labelSmall())
                        .foregroundStyle(AppColors.gray500)
                    Picker("", selection: $target) {
                        ForEach(NotificationTarget.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private func fieldRow<Content: View>(
        label: LocalizedStringKey,
        alignTop: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignTop ? .top : .center, spacing: 14) {
            Image(systemName: label == "admin.notification.field.title" ? "textformat" : "text.alignleft")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.boltGreen)
                .frame(width: 24)
                .padding(.top, alignTop ? 4 : 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.gray500)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white)
    }

    private var sendButton: some View {
        TRAPrimaryButton(
            title: "admin.notification.send",
            isLoading: isSending,
            isDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty ||
                        messageBody.trimmingCharacters(in: .whitespaces).isEmpty
        ) {
            Task { await sendNotification() }
        }
    }

    private func sendNotification() async {
        isSending = true
        defer { isSending = false }

        #if canImport(FirebaseFunctions)
        let functions = Functions.functions()
        let callable = functions.httpsCallable("sendAdminNotification")
        do {
            let response = try await callable.call([
                "title": title.trimmingCharacters(in: .whitespaces),
                "body": messageBody.trimmingCharacters(in: .whitespaces),
                "target": target.firestoreValue,
            ])
            if let data = response.data as? [String: Any],
               let sent = data["sent"] as? Int,
               let total = data["total"] as? Int {
                result = SendResult(
                    message: "Melding verzonden naar \(sent) van \(total) apparaten.",
                    isError: false
                )
            } else {
                result = SendResult(message: "Melding verzonden.", isError: false)
            }
            title = ""
            messageBody = ""
        } catch {
            result = SendResult(message: error.localizedDescription, isError: true)
        }
        #else
        result = SendResult(
            message: "FirebaseFunctions is niet beschikbaar in deze build.",
            isError: true
        )
        #endif
    }
}

#Preview {
    AdminNotificationView()
}
