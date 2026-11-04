import Foundation
import TypingCore

/// Тексты подсказок (1–3 предложения). Ключ — русский текст в `Localizable.strings`.
enum HelpText {
    static var fireFull: String {
        String(localized: "Полный огонь: за день набрано время дневной цели и завершено хотя бы одно упражнение.")
    }
    static var fireHalf: String {
        String(localized: "Половинный огонь: упражнение завершено, но дневная цель ещё не набрана. Серия всё равно продолжается.")
    }
    static var fireNone: String {
        String(localized: "Пропуск: в этот день не завершено ни одного упражнения. Серия прервётся, если нет заморозки.")
    }
    static var freezes: String {
        String(localized: "Заморозка закрывает один пропущенный день, и серия не прерывается. Новая выдаётся за каждые 7 полных дней подряд, больше двух не копится. Тратится сама, если день пропущен.")
    }
    static var fireRepaired: String {
        String(localized: "День спасён двойной целью на следующий день. Не чаще раза в 7 дней и только без заморозок.")
    }
    static var level: String {
        String(localized: "Опыт начисляется за время занятий (точная работа ценится выше), за уроки, звёзды, пороги этапов, полные дни и выполненные испытания. Опыт не сгорает, но уровень считается заново по всей истории: если поднять цель дня, старые дни без записанной цели пересчитаются, и уровень может опуститься.")
    }
    static var challenges: String {
        String(localized: "Три испытания недели и одно месяца подбираются заново каждый понедельник и первого числа. Выполненное испытание даёт опыт, а все три за неделю — награду сверху.")
    }
    /// Шкала рангов скорости: каждые 100 зн/мин — ступень, названия — те же, что в рекордах (`YearText`).
    static var speedRank: String {
        let steps = SpeedRank.allCases.map { "\($0.rawValue * 100)+ — \(YearText.title($0))" }.joined(separator: "; ")
        return String(localized: "Ранг скорости зависит от лучшей скорости на языке: каждые 100 зн/мин — новая ступень, независимо от единицы в настройках. Шкала: \(steps).")
    }
    static var repair: String {
        String(localized: "Вчерашний день пропущен, но серию можно спасти: наберите сегодня двойную цель. Починка действует не чаще раза в 7 дней и только если нет заморозок.")
    }
    static var spark: String {
        String(localized: "«Искра» — вторая серия: дни, когда завершено хотя бы одно упражнение, в том числе один шаг урока. В отличие от огня, заморозки и починка здесь не действуют: пропуск обнуляет счёт подряд, а «всего» считает все такие дни.")
    }
    /// Строка под подписью «Искра» на главной.
    static var sparkSummary: String {
        String(localized: "Дни подряд хотя бы с одним упражнением, без заморозок.")
    }
    static var fireMode: String {
        String(localized: "Огонь — главная серия: дни подряд, когда завершено хотя бы одно упражнение. Набрана цель дня — огонь полный, нет — половинный, но серия продолжается. Пропущенный день закрывает заморозка или починка.")
    }
    /// Строка под подписью «Огонь» на главной.
    static var fireSummary: String {
        String(localized: "Дни подряд с занятиями; пропуск закрывает заморозка.")
    }
    static var goalDays: String {
        String(localized: "«Цель» — дни, когда набрано время дневной цели того дня, то есть полный огонь. Заморозки здесь не действуют: «подряд» — полные дни без перерыва, «всего» — все полные дни.")
    }
    static var weekStrip: String {
        String(localized: "Текущая неделя: огонь — день с занятиями, снежинка — заморозка, пластырь — починка, кружок — пропуск. Сегодня обведено пунктиром, дни впереди бледные.")
    }
    static var futureDay: String {
        String(localized: "Этот день ещё впереди.")
    }
    static var firstWeekday: String {
        String(localized: "Влияет на ленту недели, календарь занятий и карточку «Мой прогресс».")
    }
    static var dailyGoal: String {
        String(localized: "Цель дня — сколько минут чистого времени нужно набрать, чтобы день стал полным огнём.")
    }
    /// Подпись под «Дневной целью» в настройках: цель фиксируется за каждым днём.
    static var dailyGoalChange: String {
        String(localized: "Новая цель действует с сегодняшнего дня; прошлые дни остаются засчитанными по цели того дня.")
    }
    static var activeTime: String {
        String(localized: "Чистое время — только время набора: паузы длиннее 5 секунд не считаются.")
    }
    static var trainingLetters: String {
        String(localized: "Буквы тренировки открываются по одной. Буква освоена, когда вы печатаете её не медленнее цели тренировки и ошибаетесь не чаще чем в 5% нажатий (после 30 нажатий). Когда освоены все открытые буквы, открывается следующая.")
    }
    static var weakSpots: String {
        String(localized: "Слабые места — клавиши и сочетания, на которых вы чаще ошибаетесь или медленнее печатаете. Упражнение собирает текст из них.")
    }
    static var fingerWeak: String {
        String(localized: "Слабый палец — точность ниже 97% за последние 14 дней (не меньше 50 нажатий). Кнопка «Точность» запускает 3 порции слов с буквами этого пальца.")
    }
    static var fingerStrong: String {
        String(localized: "Сильный палец — точность от 99% (не меньше 100 нажатий) и скорость не ниже порога адаптивной тренировки. Кнопка «Скорость» запускает 4 порции с целью на 10% выше вашей скорости на этом пальце.")
    }
    static var refresh: String {
        String(localized: "«Освежить» — одна проверка урока заново. Урок сдан не выше ★★, поэтому он возвращается через 1, 3 и 7 дней; результат ★★★ и выше закрывает возврат.")
    }
    static var hardLesson: String {
        String(localized: "«Трудный» — урок не дался с трёх «Освежить» подряд. Он возвращается раз в 14 дней, пока проверка не наберёт ★★★, а его буквы чаще попадают в «Повтор».")
    }
    static var speedUnits: String {
        String(localized: "Знаки в минуту — сколько символов, включая пробелы, вы набираете за минуту; считаются знаки после первого — первый запускает таймер. WPM — слова в минуту, слово считается за 5 знаков.")
    }
    static var dayStart: String {
        String(localized: "Новый день начинается в выбранный час, а не в полночь: при начале в 4:00 занятие в 2 часа ночи засчитывается предыдущему дню.")
    }
    static var hintMode: String {
        String(localized: "Как экранная клавиатура подсказывает следующую клавишу. «По курсу» — как задумано в уроке: подсказки постепенно убираются.")
    }
    static var spaceThumb: String {
        String(localized: "Подсвечивает половину пробела: жмите его большим пальцем руки, противоположной предыдущей букве.")
    }
    static var adaptiveTarget: String {
        String(localized: "Скорость, к которой стремится адаптивная тренировка: буква освоена, когда вы печатаете её не медленнее.")
    }
    static var keyboardSize: String {
        String(localized: "Ширина клавиши экранной клавиатуры в уроках. Пока двигаете ползунок, клавиатура показывается в реальном размере.")
    }
    static var keyboardOffset: String {
        String(localized: "Сдвигает экранную клавиатуру влево или вправо, например под центр клавиатуры ноутбука.")
    }
    static var keyboardReset: String {
        String(localized: "Вернёт размер и сдвиг экранной клавиатуры к исходным.")
    }
    static var soundsReset: String {
        String(localized: "Включит все звуки и вернёт их громкость к исходной.")
    }
    static var quitOnClose: String {
        String(localized: "Если выключено, закрытие окна оставляет приложение в Dock, а щелчок по значку открывает окно снова.")
    }
    static var interfaceLanguage: String {
        String(localized: "Язык меню и экранов. Язык курса выбирается отдельно, внизу боковой панели.")
    }
    static var reminderSchedule: String {
        String(localized: "Когда приходят напоминания. Если день уже полный огонь, оставшиеся напоминания на сегодня не придут.")
    }
    static var reminderTone: String {
        String(localized: "Тон текстов: спокойный, шуточный или вперемешку. «Взрослые» шутки — только при включённом «Взрослом юморе».")
    }
    static var reminderEscalating: String {
        String(localized: "Каждое следующее напоминание за день настойчивее: первое мягкое, второе настойчивое, третье и дальше — драма. Чаще они не приходят: сколько и когда — задаёт расписание, а единственное напоминание в день всегда мягкое. Когда день стал полным огнём, оставшиеся на сегодня отменяются.")
    }
    /// Первое предложение подсказки — подпись под переключателем (полный текст — в «?» и во всплывающей подсказке).
    static var reminderTest: String {
        String(localized: "Через несколько секунд придёт пробное уведомление: так будут выглядеть напоминания.")
    }
    static var reminderEscalatingSummary: String {
        String(localized: "Каждое следующее напоминание за день настойчивее: первое мягкое, второе настойчивое, третье и дальше — драма.")
    }

    /// Подсказка к статусу дня: огонь, заморозка или пропуск.
    static func fire(_ status: DayStatus) -> String {
        switch status {
        case .full: fireFull
        case .half: fireHalf
        case .frozen: freezes
        case .repaired: fireRepaired
        case .none: fireNone
        }
    }

    static var dayPlan: String {
        String(localized: "План на сегодня собирается из истории каждый день: разминка, урок, тренировка и текст под вашу цель дня. Пункт засчитан, когда упражнение из него завершено. Урок засчитывает проверка урока или половина шагов урока — из плана или с карты курса.")
    }

    /// Все тексты — для теста длины.
    static var all: [String] {
        [fireFull, fireHalf, fireNone, freezes, fireRepaired, weekStrip, dailyGoal, activeTime, trainingLetters, weakSpots,
         speedUnits, dayStart, hintMode, spaceThumb, adaptiveTarget, keyboardSize, keyboardOffset, quitOnClose, interfaceLanguage,
         reminderSchedule, reminderTone, reminderEscalating, reminderEscalatingSummary, keyboardReset, soundsReset, dailyGoalChange, spark, level, challenges, speedRank, repair, goalDays, futureDay, firstWeekday, reminderTest, refresh, hardLesson, fingerWeak, fingerStrong, dayPlan, sparkSummary, fireMode, fireSummary]
    }
}
