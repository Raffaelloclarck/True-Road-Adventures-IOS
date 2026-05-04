import SwiftUI

struct SupportTopicView: View {
    @State private var selectedTopic: SupportTopic? = nil
    @State private var searchText = ""

    private var filteredTopics: [SupportTopic] {
        if searchText.isEmpty { return SupportTopic.allCases }
        return SupportTopic.allCases.filter {
            NSLocalizedString($0.rawTitleKey, comment: "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                searchBar
                categoriesGrid
                contactSection
            }
            .padding(16)
        }
        .background(AppColors.backgroundLight)
        .navigationTitle(Text("support.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTopic) { topic in
            topicSheet(topic: topic)
        }
    }

    private var searchBar: some View {
        TRATextField(placeholder: "support.search.placeholder", text: $searchText, icon: "magnifyingglass")
    }

    private var categoriesGrid: some View {
        VStack(spacing: 0) {
            ForEach(Array(filteredTopics.enumerated()), id: \.offset) { index, topic in
                Button {
                    selectedTopic = topic
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppColors.boltGreen.opacity(0.1))
                                .frame(width: 40, height: 40)
                            Image(systemName: topic.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(AppColors.boltGreen)
                        }
                        Text(topic.titleKey)
                            .font(AppFont.bodyMedium())
                            .foregroundStyle(AppColors.gray900)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.gray300)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                if index < filteredTopics.count - 1 {
                    Divider().padding(.leading, 70)
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private var contactSection: some View {
        VStack(spacing: 12) {
            Text("support.more.title")
                .font(AppFont.titleSmall())
                .foregroundStyle(AppColors.gray900)
                .frame(maxWidth: .infinity, alignment: .leading)

            TRAPrimaryButton(title: "support.contact.chat") {
                if let url = URL(string: "mailto:support@trueroadadventures.nl") {
                    UIApplication.shared.open(url)
                }
            }
            TRASecondaryButton(title: "support.contact.call", icon: "phone.fill") {
                if let url = URL(string: "tel://+31202345678") {
                    UIApplication.shared.open(url)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.r16))
    }

    private func topicSheet(topic: SupportTopic) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppColors.boltGreenLight)
                                .frame(width: 52, height: 52)
                            Image(systemName: topic.icon)
                                .font(.system(size: 22))
                                .foregroundStyle(AppColors.boltGreen)
                        }
                        Text(topic.titleKey)
                            .font(AppFont.titleMedium())
                            .foregroundStyle(AppColors.gray900)
                    }

                    Text(topic.contentKey)
                        .font(AppFont.bodyMedium())
                        .foregroundStyle(AppColors.gray700)
                        .lineSpacing(6)

                    TRAPrimaryButton(title: "support.contact.cta") {
                        if let url = URL(string: "mailto:support@trueroadadventures.nl?subject=\(NSLocalizedString(topic.rawTitleKey, comment: ""))") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle(topic.titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        selectedTopic = nil
                    } label: {
                        Text("support.close")
                            .font(AppFont.labelMedium())
                            .foregroundStyle(AppColors.boltGreen)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

enum SupportTopic: String, CaseIterable, Identifiable {
    case payment, promotions, safety, privacy, savedPlaces, language, account, rides

    var id: String { rawValue }

    var rawTitleKey: String {
        switch self {
        case .payment:     return "support.topic.payment"
        case .promotions:  return "support.topic.promotions"
        case .safety:      return "support.topic.safety"
        case .privacy:     return "support.topic.privacy"
        case .savedPlaces: return "support.topic.saved_places"
        case .language:    return "support.topic.language"
        case .account:     return "support.topic.account"
        case .rides:       return "support.topic.ride_issues"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .payment:     return "support.topic.payment"
        case .promotions:  return "support.topic.promotions"
        case .safety:      return "support.topic.safety"
        case .privacy:     return "support.topic.privacy"
        case .savedPlaces: return "support.topic.saved_places"
        case .language:    return "support.topic.language"
        case .account:     return "support.topic.account"
        case .rides:       return "support.topic.ride_issues"
        }
    }

    var contentKey: LocalizedStringKey {
        switch self {
        case .payment:     return "support.body.payment"
        case .promotions:  return "support.body.promotions"
        case .safety:      return "support.body.safety"
        case .privacy:     return "support.body.privacy"
        case .savedPlaces: return "support.body.saved_places"
        case .language:    return "support.body.language"
        case .account:     return "support.body.account"
        case .rides:       return "support.body.ride_issues"
        }
    }

    var icon: String {
        switch self {
        case .payment:     return "creditcard.fill"
        case .promotions:  return "gift.fill"
        case .safety:      return "shield.fill"
        case .privacy:     return "lock.fill"
        case .savedPlaces: return "heart.fill"
        case .language:    return "globe"
        case .account:     return "person.fill"
        case .rides:       return "car.fill"
        }
    }
}

#Preview { NavigationStack { SupportTopicView() } }
