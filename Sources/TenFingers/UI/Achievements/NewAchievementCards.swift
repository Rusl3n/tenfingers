import SwiftUI
import TypingCore

/// Что получено в единице: ачивка, «Повтор ×N» у повторного получения (`nil` — «Новая») и значение получения
/// (скорость рекорда, звёзды, ступень, число заходов, минуты).
struct EarnedCard: Identifiable, Equatable {
    let achievement: Achievement
    /// `nil` — первое получение («Новая»); иначе «Повтор ×N», N ≥ 2.
    let repeatCount: Int?
    let value: Double?

    init(_ achievement: Achievement, repeatCount: Int? = nil, value: Double? = nil) {
        self.achievement = achievement
        self.repeatCount = repeatCount
        self.value = value
    }

    var id: String { achievement.id }

    /// Карточки итога по результату проверки: разовые новые — как раньше; повторяемые — по выдачам, одна карточка
    /// на ачивку (последняя выдача: у неё наибольшее «×N» и свежее значение). Ачивка, впервые полученная в этой
    /// проверке (даже сразу несколько раз), — «Новая», а не «Повтор».
    static func cards(from outcome: AchievementService.Outcome) -> [EarnedCard] {
        let granted = Set(outcome.grants.map(\.achievement.id))
        let firstTime = Set(outcome.new.map(\.id))
        var cards = outcome.new.filter { !granted.contains($0.id) }.map { EarnedCard($0) }
        var last: [String: AchievementService.NewGrant] = [:]
        var order: [String] = []
        for grant in outcome.grants {
            if last.updateValue(grant, forKey: grant.achievement.id) == nil { order.append(grant.achievement.id) }
        }
        for id in order {
            guard let grant = last[id] else { continue }
            let repeated = grant.count >= 2 && !firstTime.contains(id)
            cards.append(EarnedCard(grant.achievement, repeatCount: repeated ? grant.count : nil,
                                    value: grant.value))
        }
        return cards
    }

    /// Копилка запуска: карточка той же ачивки заменяется новой (на итоге урока одна «Повтор ×N», а не несколько).
    static func merged(_ existing: [EarnedCard], with new: [EarnedCard]) -> [EarnedCard] {
        let ids = Set(new.map(\.id))
        return existing.filter { !ids.contains($0.id) } + new
    }

    /// Строка со значением: «Новый рекорд: 231 зн/мин» у рекорда скорости, у прочих — само значение («★★★»,
    /// «ступень 60 зн/мин»); без значения — `nil`.
    func valueLine(unit: SpeedUnit) -> String? {
        guard let value else { return nil }
        let text = Formatting.grantValue(value, for: achievement, unit: unit)
        guard !text.isEmpty else { return nil }
        return achievement.id == "speed.record" ? String(localized: "Новый рекорд: \(text)") : text
    }

    /// «Новая ачивка» или «Повтор ×N».
    var headline: String {
        repeatCount.map { String(localized: "Повтор ×\($0)") } ?? String(localized: "Новая ачивка")
    }
}

/// Карточки на экране итога (шага, урока, повтора шага, порции тренировки и практики): «Полный огонь» (если день
/// стал полным) первой, затем новые ачивки — значок, название, шутка и «Поделиться». Висят, пока открыт экран итога;
/// тоста после упражнения нет. Всего до `limit` карточек в ряд, остальные — ссылкой «И ещё N — в разделе «Ачивки»»
/// (`openAchievements`).
struct NewAchievementCards: View {
    let achievements: [EarnedCard]
    var fullFlame: FullFlame?
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @AppStorage(SettingsKey.adultHumor) private var adultHumor = SettingsDefault.adultHumor
    @Environment(\.openAchievements) private var openAchievements
    @State private var share: ShareCard?

    nonisolated static let limit = 3

    /// Видимые ачивки в порядке получения: первые карточками, сколько ещё — числом. Карточек всего `limit`,
    /// «Полный огонь» (`fullFlame`) занимает одно место. Скрытые «Взрослым юмором» не показываются и не считаются.
    nonisolated static func content(_ achievements: [EarnedCard], fullFlame: Bool = false, adultHumor: Bool)
        -> (shown: [EarnedCard], more: Int) {
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
                    ForEach(content.shown, id: \.id) { card in
                        NewAchievementCard(card: card, unit: SpeedUnit(rawValue: speedUnit) ?? .cpm,
                                           share: ShareAvailability.canShare(card.achievement, adultHumor: adultHumor)
                                               ? { share = ShareCard(.achievement(card.achievement, .now)) } : nil)
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

/// Одна карточка: «Новая ачивка» или «Повтор ×N», значок в цвете категории, название, шутка и ссылка «Поделиться».
private struct NewAchievementCard: View {
    let card: EarnedCard
    let unit: SpeedUnit
    let share: (() -> Void)?
    @Environment(\.palette) private var palette

    static let width: CGFloat = 210

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Текст основным цветом (жёлтый плохо читается на светлых палитрах), жёлтая только иконка.
            Label {
                Text(card.headline)
            } icon: {
                Image(systemName: "trophy.fill").foregroundStyle(AchievementToasts.tint)
            }
            .font(.caption.weight(.semibold))
            HStack(alignment: .top, spacing: 10) {
                AchievementIcon(achievement: card.achievement, earned: true, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.achievement.title).font(.headline)
                    if let line = card.valueLine(unit: unit) { Text(line).font(.callout.weight(.semibold)) }
                    Text(card.achievement.detail).font(.callout).foregroundStyle(.secondary)
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
