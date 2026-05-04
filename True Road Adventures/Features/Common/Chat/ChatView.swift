import SwiftUI
#if canImport(FirebaseFirestore)
import FirebaseFirestore
import FirebaseAuth
#endif

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let text: String
    let senderId: String
    let isOwn: Bool
    let timestamp: Date
}

struct ChatView: View {
    let rideId: String
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var listenerHandle: Any?

    private var currentUserId: String {
        authService.state.user?.id ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            messageList
            inputBar
        }
        .background(AppColors.backgroundLight)
        .navigationBarHidden(true)
        .ignoresSafeArea(edges: .bottom)
        .task { await startListening() }
        .onDisappear { stopListening() }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.gray900)
            }
            .buttonStyle(.plain)

            ZStack {
                Circle().fill(AppColors.boltGreenLight).frame(width: 40, height: 40)
                Image(systemName: "person.fill").foregroundStyle(AppColors.boltGreen)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("chat.title").font(AppFont.titleSmall()).foregroundStyle(AppColors.gray900)
                Text("chat.ride_prefix \(rideId.prefix(8))").font(AppFont.labelSmall()).foregroundStyle(AppColors.gray500)
            }

            Spacer()

            Button {
                if let url = URL(string: "tel://112") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.boltGreen)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.isOwn { Spacer(minLength: 60) }
            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(AppFont.bodyMedium())
                    .foregroundStyle(message.isOwn ? .white : AppColors.gray900)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isOwn ? AppColors.boltGreenDeep : Color(hex: 0xE5E7EB))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Text(message.timestamp.formatted(.dateTime.hour().minute()))
                    .font(AppFont.labelSmall())
                    .foregroundStyle(AppColors.gray500)
                    .padding(.horizontal, 4)
            }
            if !message.isOwn { Spacer(minLength: 60) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField(text: $messageText) {
                Text("chat.message.placeholder")
            }
                .font(AppFont.bodyLarge())
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(AppColors.backgroundCard)
                .clipShape(Capsule())

            Button {
                Task { await sendMessage() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(messageText.isEmpty ? AppColors.gray300 : AppColors.boltGreen)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(messageText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 30)
        .background(Color.white)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: -2)
    }

    // MARK: - Firestore

    private func startListening() async {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let ref = db.collection("rides").document(rideId).collection("messages")
            .order(by: "timestamp", descending: false)

        listenerHandle = ref.addSnapshotListener { snapshot, _ in
            guard let docs = snapshot?.documents else { return }
            let loaded: [ChatMessage] = docs.compactMap { doc -> ChatMessage? in
                let data = doc.data()
                guard let text = data["text"] as? String,
                      let senderId = data["senderId"] as? String,
                      let ts = data["timestamp"] as? Timestamp else { return nil }
                return ChatMessage(
                    id: doc.documentID,
                    text: text,
                    senderId: senderId,
                    isOwn: senderId == self.currentUserId,
                    timestamp: ts.dateValue()
                )
            }
            self.messages = loaded
        }
        #endif
    }

    private func stopListening() {
        #if canImport(FirebaseFirestore)
        if let handle = listenerHandle as? ListenerRegistration {
            handle.remove()
        }
        #endif
        listenerHandle = nil
    }

    private func sendMessage() async {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        messageText = ""

        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let ref = db.collection("rides").document(rideId).collection("messages")
        _ = try? await ref.addDocument(data: [
            "text": text,
            "senderId": currentUserId,
            "timestamp": Timestamp(date: Date())
        ])
        #else
        let msg = ChatMessage(
            id: UUID().uuidString,
            text: text,
            senderId: currentUserId,
            isOwn: true,
            timestamp: .now
        )
        messages.append(msg)
        #endif
    }
}

#Preview {
    ChatView(rideId: "demo-ride")
        .environmentObject(AuthService(repository: InMemoryAuthRepository()))
}
