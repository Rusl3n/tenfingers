import Foundation

public enum ReminderScheduleMode: String, CaseIterable, Sendable { case once, thrice, interval }
public enum ReminderTone: String, CaseIterable, Sendable { case normal, funny, mixed }
public enum ReminderStage: Int, CaseIterable, Sendable { case soft = 0, insistent, drama }

/// Текст напоминания: ключ (русский текст с `{streak}`/`{minutes}`) и числа для подстановки.
public struct ReminderLine: Equatable, Sendable {
    public let key: String
    public let streak: Int
    public let minutes: Int

    public init(key: String, streak: Int, minutes: Int) {
        self.key = key
        self.streak = streak
        self.minutes = minutes
    }
}

/// Каталог текстов напоминаний. Ключ фразы — русский текст в ресурсах ядра (перевод — там же).
public enum ReminderCatalog {
    /// Какое число нужно фразе: серия (`{streak}`), минуты до огня (`{minutes}`) или никакое.
    public enum Need: Sendable { case none, streak, minutes }

    /// `tone` бывает только `.normal` или `.funny`; «Вперемешку» — их объединение.
    public struct Phrase: Sendable {
        public let key: String
        public let tone: ReminderTone
        public let stage: ReminderStage
        public let adult: Bool
        public let need: Need
    }

    /// Положение дел на момент напоминания: определяет, какие числа можно показать.
    public enum Context: Equatable, Sendable {
        /// Сегодня ещё нет огня, серия идёт.
        case atRisk(streak: Int)
        /// Сегодня ещё нет огня, серии нет.
        case fresh
        /// Сегодня половинный огонь: осталось `minutes` минут.
        case almost(minutes: Int)
        /// Будущий день: числа к тому времени устареют, годятся только фразы без них.
        case later
    }

    private static func phrase(_ tone: ReminderTone, _ stage: ReminderStage, _ need: Need, adult: Bool = false,
                               _ key: String) -> Phrase {
        Phrase(key: key, tone: tone, stage: stage, adult: adult, need: need)
    }

    public static let phrases: [Phrase] = [
        phrase(.normal, .soft, .none, "Пора позаниматься: пара упражнений — и день засчитан"),
        phrase(.normal, .soft, .none, "Самое время для короткой тренировки"),
        phrase(.normal, .soft, .none, "Несколько минут за клавиатурой — и пальцы скажут спасибо"),
        phrase(.normal, .soft, .streak, "Серия {streak} дн. ждёт продолжения"),
        phrase(.normal, .soft, .streak, "Серия {streak} дн. — продолжим сегодня?"),
        phrase(.normal, .soft, .minutes, "До полного огня осталось {minutes} мин"),
        phrase(.normal, .soft, .minutes, "Ещё {minutes} мин — и день будет полным"),
        phrase(.normal, .insistent, .none, "Сегодня вы ещё не занимались. Самое время начать"),
        phrase(.normal, .insistent, .none, "День идёт, а упражнений пока нет. Пять минут найдётся?"),
        phrase(.normal, .insistent, .streak, "Серия {streak} дн. под угрозой — займитесь сегодня"),
        phrase(.normal, .insistent, .streak, "Не дайте серии в {streak} дн. оборваться"),
        phrase(.normal, .insistent, .minutes, "{minutes} мин до полного огня — не останавливайтесь"),
        phrase(.normal, .insistent, .minutes, "Полный огонь близко: ещё {minutes} мин"),
        phrase(.normal, .drama, .none, "Последний шанс: день вот-вот закончится без занятий"),
        phrase(.normal, .drama, .none, "Вечер, а клавиатура скучает. Хотя бы одно упражнение?"),
        phrase(.normal, .drama, .streak, "Серия {streak} дн. может сгореть сегодня. Спасите её!"),
        phrase(.normal, .drama, .streak, "{streak} дн. подряд — неужели бросить сегодня?"),
        phrase(.normal, .drama, .minutes, "Всего {minutes} мин отделяют вас от полного огня. Не сдавайтесь!"),
        phrase(.normal, .drama, .minutes, "Огонь почти полный: {minutes} мин — и день ваш"),
        phrase(.funny, .soft, .none, "Клавиатура соскучилась. Погладьте её пальцами"),
        phrase(.funny, .soft, .none, "Пальцы просят разминки. Не отказывайте им"),
        phrase(.funny, .soft, .none, "Буквы сами себя не напечатают"),
        phrase(.funny, .soft, .streak, "Огонёк серии ({streak} дн.) просит дров"),
        phrase(.funny, .soft, .minutes, "Огонь горит вполсилы. Подкиньте {minutes} мин"),
        phrase(.funny, .insistent, .none, "Клавиатура начала покрываться пылью. Ну почти"),
        phrase(.funny, .insistent, .none, "Ваши пальцы подали жалобу: их не тренируют"),
        phrase(.funny, .insistent, .streak, "Серия {streak} дн. нервно поглядывает на часы"),
        phrase(.funny, .insistent, .streak, "Звонила серия {streak} дн. Просила её не бросать"),
        phrase(.funny, .insistent, .minutes, "{minutes} мин до полного огня — это меньше одной серии сериала"),
        phrase(.funny, .insistent, .minutes, "Огонь просит ещё {minutes} мин. Он не отстанет"),
        phrase(.funny, .drama, .none, "Клавиши плачут. Особенно пробел"),
        phrase(.funny, .drama, .none, "Если сегодня не позанимаетесь, мизинцы обидятся навсегда"),
        phrase(.funny, .drama, .streak, "Серия {streak} дн. пишет завещание. Вы ещё можете её спасти"),
        phrase(.funny, .drama, .streak, "Где-то грустит серия длиной {streak} дн. Только вы можете помочь"),
        phrase(.funny, .drama, .minutes, "Огонь гаснет! Срочно нужны {minutes} мин"),
        phrase(.funny, .drama, .minutes, "{minutes} мин до полного огня. Драма века или победа дня?"),
        phrase(.funny, .soft, .none, adult: true, "Ваши пальцы заскучали. Займите их чем-нибудь приличным — например, печатью"),
        phrase(.funny, .insistent, .streak, adult: true, "Серия {streak} дн. Бросать её сейчас — как уйти со свидания до десерта"),
        phrase(.funny, .drama, .none, adult: true, "Клавиатура ждёт вас, как бывшая в три часа ночи. Только эта — полезная"),
        phrase(.funny, .drama, .minutes, adult: true, "Ещё {minutes} мин. Не останавливайтесь на самом интересном"),
        phrase(.funny, .soft, .minutes, adult: true, "Огонь разгорается. Ещё {minutes} мин — и будет жарко"),
        phrase(.funny, .insistent, .none, adult: true, "Пальцы без тренировки — как вечеринка без музыки. Включайте"),
    ]

    /// Кандидаты для напоминания: тон (`.mixed` — оба), ступень, «взрослые» — только при `adultHumor`;
    /// числа — по контексту: с серией — фразы без чисел или с серией, без серии — без чисел,
    /// с половинным огнём — без чисел или с минутами, будущий день — без чисел.
    public static func candidates(tone: ReminderTone, stage: ReminderStage, adultHumor: Bool,
                                  context: Context) -> [Phrase] {
        let allowed: Set<Need> = switch context {
        case .atRisk: [.none, .streak]
        case .almost: [.none, .minutes]
        case .fresh, .later: [.none]
        }
        return phrases.filter {
            (tone == .mixed || $0.tone == tone) && $0.stage == stage && (adultHumor || !$0.adult)
                && allowed.contains($0.need)
        }
    }

    /// Детерминированный выбор: FNV-1a 64 от `"<логический день>#<номер слота>"` по модулю числа кандидатов.
    /// Один и тот же слот в один и тот же день всегда даёт один и тот же текст, сколько бы раз ни пересчитывали план.
    public static func pick(context: Context, stage: ReminderStage, tone: ReminderTone, adultHumor: Bool,
                            dayKey: String, slot: Int) -> ReminderLine? {
        let found = candidates(tone: tone, stage: stage, adultHumor: adultHumor, context: context)
        guard !found.isEmpty else { return nil }
        let chosen = found[Int(fnv1a("\(dayKey)#\(slot)") % UInt64(found.count))]
        var streak = 0, minutes = 0
        switch (chosen.need, context) {
        case (.streak, .atRisk(let value)): streak = value
        case (.minutes, .almost(let value)): minutes = value
        default: break
        }
        return ReminderLine(key: chosen.key, streak: streak, minutes: minutes)
    }

    /// Готовый текст: перевод ключа и подстановка чисел. `localization` — `"ru"`/`"en"`; без неё — язык системы.
    public static func render(_ line: ReminderLine, localization: String? = nil) -> String {
        CoreText.localized(line.key, localization: localization)
            .replacingOccurrences(of: "{streak}", with: String(line.streak))
            .replacingOccurrences(of: "{minutes}", with: String(line.minutes))
    }

    /// FNV-1a, 64 бита, по байтам UTF-8.
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
