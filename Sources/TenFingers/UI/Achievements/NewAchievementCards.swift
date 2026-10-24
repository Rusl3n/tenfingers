import SwiftUI
import TypingCore

/// Карточки на экране итога (шага, урока, повтора шага, порции тренировки и практики): «Полный огонь» (если день
/// стал полным) первой, затем новые ачивки — значок, название, шутка и «Поделиться». Висят, пока открыт экран итога;
/// тоста после упражнения нет. Всего до `limit` карточек в ряд, остальные — ссылкой «И ещё N — в разделе «Ачивки»»
/// (`openAchievements`).
struct NewAchievementCards: View {
    let achievements: [Achievement]
    var fullFlame: FullFlame?
    @AppStorage(SettingsKey.adultHumor) private var adultHumor = SettingsDefault.adultHumor
    @Environment(\.openAchievements) private var openAchievements
    @State private var share: ShareCard?

    nonisolated static let limit = 3

    /// Видимые ачивки в порядке получения: первые карточками, сколько ещё — числом. Карточек всего `limit`,
    /// «Полный огонь» (`fullFlame`) занимает одно место. Скрытые «Взрослым юмором» не показываются и не считаются.
    nonisolated static func content(_ achievements: [Achievement], fullFlame: Bool = false, adultHumor: Bool)
        -> (shown: [Achievement], more: Int) {
        let visible = AchievementVisibility.visible(achievements, adultHumor: adultHumor)
        let room = limit - (fullFlame ? 1 : 0)
        return (Array(visible.prefix(room)), max(visible.count - room, 0))
    }

    var body: some View {
        let content = Self.content(achievements, fullFlame: fullFlame != nil, adultHumor: adultHumor)
        if fullFlame != nil || !content.shown.isEmpty {
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    if let fullFlame { FullFlameCard(flame: fullFlame) }
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

/// Карточка «Полный огонь»: значок огня, «Цель дня выполнена», серия и «Поделиться» (карточка «Мой прогресс»,
/// как у серии на главной).
struct FullFlameCard: View {
    let flame: FullFlame
    @Environment(\.palette) private var palette
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(SettingsKey.dayStartHour) private var dayStartHour = SettingsDefault.dayStartHour
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = SettingsDefault.dailyGoalMinutes
    @State private var share: ShareCard?

    nonisolated static let icon = "flame.fill"

    /// «5 дней подряд» (число дней склоняется по языку интерфейса).
    nonisolated static func streakText(_ days: Int, bundle: Bundle = .main, locale: Locale? = nil) -> String {
        let locale = locale ?? Formatting.interfaceLocale(bundle: bundle)
        let count = Formatting.days(days, bundle: bundle, locale: locale)
        return String(localized: "\(count) подряд", bundle: bundle, locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Полный огонь").font(.caption.weight(.semibold))
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: Self.icon)
                    .font(.system(size: 34))
                    .foregroundStyle(Color.orange)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Цель дня выполнена").font(.headline)
                    if flame.days > 0 {
                        Text(Self.streakText(flame.days)).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            ShareLinkButton {
                share = ShareCard.openProgress(context: modelContext, goalSeconds: Double(dailyGoal) * 60,
                                               dayStartHour: dayStartHour, toasts: toasts)
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: NewAchievementCard.width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.6), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .shareSheet($share)
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
