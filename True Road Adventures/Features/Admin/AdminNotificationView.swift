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

    private let titleLimit = 60
    private let bodyLimit = 200

    enum NotificationTarget: String, CaseIterable, Identifiable {
        case all, riders, drivers
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:     return "Iedereen"
            case .riders:  return "Rijders"
            case .drivers: return "Chauffeurs"
            }
        }
        var icon: String {
            switch self {
            case .all:     return "globe"
            case .riders:  return "figure.walk"
            case .drivers: return "car.fill"
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

                    VStack(spacing: 12) {
                        titleCard
                        bodyCard
                        targetCard
                        if isFormValid {
                            previewCard
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .animation(.easeInOut(duration: 0.25), value: isFormValid)

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

    // MARK: - Header

    private var pageHeader: some View {
        ZStack(alignment: .bottom) {
            AppColors.boltGreen
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: AppRadius.r32,
                        bottomTrailingRadius: AppRadius.r32
                    )
                )
                .frame(height: 190)

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 68, height: 68)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

                Text("Notificaties")
                    .font(AppFont.titleLarge())
                    .foregroundStyle(.white)

                Text("Stuur een melding naar rijders of chauffeurs")
                    .font(AppFont.bodySmall())
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Form Cards

    private var titleCard: some View {
        HStack(spacing: 12) {
            iconBadge(systemName: "textformat")
            VStack(alignment: .leading, spacing: 4) {
                Text("Titel")
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.gray500)
                TextField("Bijv. Nieuwe rit beschikbaar...", text: $title)
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(AppColors.gray900)
                    .onChange(of: title) { _, new in
                        if new.count > titleLimit { title = String(new.prefix(titleLimit)) }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(title.count)/\(titleLimit)")
                .font(AppFont.labelSmall())
                .foregroundStyle(title.count >= titleLimit ? AppColors.errorRed : AppColors.gray300)
                .monospacedDigit()
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var bodyCard: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                iconBadge(systemName: "text.alignleft")
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bericht")
                        .font(AppFont.labelSmall())
                        .foregroundStyle(AppColors.gray500)
                    TextField(
                        "Schrijf hier je melding...",
                        text: $messageBody,
                        axis: .vertical
                    )
                    .lineLimit(4, reservesSpace: true)
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(AppColors.gray900)
                    .onChange(of: messageBody) { _, new in
                        if new.count > bodyLimit { messageBody = String(new.prefix(bodyLimit)) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Text("\(messageBody.count)/\(bodyLimit)")
                .font(AppFont.labelSmall())
                .foregroundStyle(messageBody.count >= bodyLimit ? AppColors.errorRed : AppColors.gray300)
                .monospacedDigit()
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var targetCard: some View {
        HStack(spacing: 12) {
            iconBadge(systemName: "person.2.fill")
            VStack(alignment: .leading, spacing: 10) {
                Text("Doelgroep")
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.gray500)

                HStack(spacing: 8) {
                    ForEach(NotificationTarget.allCases) { t in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                target = t
                            }
                        } label: {
                            Text(t.label)
                                .font(AppFont.labelMedium())
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(
                                    target == t
                                        ? AppColors.boltGreen
                                        : AppColors.gray100
                                )
                                .foregroundStyle(
                                    target == t ? Color.white : AppColors.gray700
                                )
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.r20))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    // MARK: - Preview Card

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.boltGreen)
                Text("Voorbeeld")
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.boltGreen)
            }

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.r8)
                        .fill(AppColors.boltGreen)
                        .frame(width: 36, height: 36)
                    Image(systemName: "bell.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("True Road Adventures")
                            .font(AppFont.labelSmall())
                            .foregroundStyle(AppColors.gray500)
                        Spacer()
                        Text("nu")
                            .font(AppFont.labelSmall())
                            .foregroundStyle(AppColors.gray300)
                    }
                    Text(title.trimmingCharacters(in: .whitespaces))
                        .font(AppFont.labelMedium())
                        .foregroundStyle(AppColors.gray900)
                        .lineLimit(1)
                    Text(messageBody.trimmingCharacters(in: .whitespaces))
                        .font(AppFont.bodySmall())
                        .foregroundStyle(AppColors.gray500)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .background(AppColors.gray50)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r12))
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func iconBadge(systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.r8)
                .fill(AppColors.boltGreenLight)
                .frame(width: 36, height: 36)
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.boltGreen)
        }
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            Task { await sendNotification() }
        } label: {
            ZStack {
                if isSending {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Melding versturen")
                            .font(AppFont.labelLarge())
                    }
                    .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                isFormValid
                    ? AppColors.boltGreen
                    : AppColors.boltGreen.opacity(0.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
            .shadow(
                color: AppColors.boltGreen.opacity(isFormValid ? 0.3 : 0),
                radius: 4, x: 0, y: 4
            )
        }
        .disabled(!isFormValid || isSending)
        .buttonStyle(.plain)
    }

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !messageBody.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Network

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
