import SwiftUI
import TypingCore

/// Карточки новых ачивок на экране итога (шага, урока, повтора шага, порции тренировки и практики): значок,
/// название, шутка и «Поделиться». Висят, пока открыт экран итога; тоста после упражнения нет.
/// До `limit` карточек в ряд, остальные — ссылкой «И ещё N — в разделе «Ачивки»» (`openAchievements`).
struct NewAchievementCards: View {
    let achievements: [Achievement]
    @AppStorage(SettingsKey.adultHumor) private var adultHumor = SettingsDefault.adultHumor
    @Environment(\.openAchievements) private var openAchievements
    @State private var share: ShareCard?

    nonisolated static let limit = 3

    /// Видимые ачивки в порядке получения: первые `limit` — карточками, сколько ещё — числом.
    /// Скрытые «Взрослым юмором» не показываются и не считаются.
    nonisolated static func content(_ achievements: [Achievement], adultHumor: Bool) -> (shown: [Achievement], more: Int) {
        let visible = AchievementVisibility.visible(achievements, adultHumor: adultHumor)
        return (Array(visible.prefix(limit)), max(visible.count - limit, 0))
    }

    var body: some View {
        let content = Self.content(achievements, adultHumor: adultHumor)
        if !content.shown.isEmpty {
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(content.shown, id: \.id) { achievement in
                        NewAchievementCard(achievement: achievement,
                                           share: ShareAvailability.canShare(achievement, adultHumor: adultHumor)
                                               ? { share = ShareCard(.achievement(achievement, .now)) } : nil)
                    }
                }
                // Карточки ряда одной высоты: по самой высокой.
                .fixedSize(horizontal: false, vertical: true)
                if content.more > 0 {
                    if let openAchievements {
                        Button { openAchievements() } label: {
                            Text("И ещё \(content.more) — в разделе «Ачивки»")
                        }
                        .buttonStyle(.link)
                    } else {
                        Text("И ещё \(content.more) — в разделе «Ачивки»").foregroundStyle(.secondary)
                    }
                }
            }
            .shareSheet($share)
        }
    }
}

/// Одна карточка: «Новая ачивка», значок в цвете категории, название, шутка и ссылка «Поделиться».
private struct NewAchievementCard: View {
    let achievement: Achievement
    let share: (() -> Void)?
    @Environment(\.palette) private var palette

    static let width: CGFloat = 210

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Текст основным цветом (жёлтый плохо читается на светлых палитрах), жёлтая только иконка.
            Label {
                Text("Новая ачивка")
            } icon: {
                Image(systemName: "trophy.fill").foregroundStyle(AchievementToasts.tint)
            }
            .font(.caption.weight(.semibold))
            HStack(alignment: .top, spacing: 10) {
                AchievementIcon(achievement: achievement, earned: true, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(achievement.title).font(.headline)
                    Text(achievement.detail).font(.callout).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let share { ShareLinkButton(action: share).font(.callout) }
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AchievementToasts.tint.opacity(0.6), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
    }
}

/// Открыть раздел «Ачивки» (как «Посмотреть» в тосте): задаёт `RootView`, идущий запуск при этом скрывается.
struct OpenAchievementsAction {
    let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @MainActor func callAsFunction() { action() }
}

extension EnvironmentValues {
    /// `nil` — вне `RootView` (тесты, картинки README): «И ещё N» остаётся текстом.
    @Entry var openAchievements: OpenAchievementsAction?
}
