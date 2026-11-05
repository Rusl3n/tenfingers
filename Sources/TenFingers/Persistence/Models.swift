import Foundation
import SwiftData
import TypingCore

@Model final class SessionRecord {
    var id: UUID
    var mode: String
    var language: String
    var lessonId: String?
    var startedAt: Date
    var endedAt: Date
    var logicalDay: String
    var activeSeconds: Double
    var chars: Int
    var errorCount: Int
    var cpm: Double
    var accuracy: Double
    var completed: Bool
    var hintLevel: String
    var maxErrorStreak: Int
    var wrongKeystrokes: Int
    /// Вид упражнения урока (`ExerciseKind.rawValue`); `nil` для режимов вне курса.
    var exerciseKind: String?
    var pinkyPresses: Int = 0
    var pinkyErrors: Int = 0
    /// Откуда текст вне курса: `adaptive`, `weak`, `words`, `symbols`, `custom`, `library:<id>`;
    /// `nil` для уроков и для записей до фазы 2.
    var source: String? = nil
    /// Нажатия и ошибки по пальцам (`FingerCounts`: JSON «палец → число»); `nil` у записей до фазы 5
    /// (поколение схемы 4).
    var fingerPresses: Data? = nil
    var fingerErrors: Data? = nil
    /// «ё» и «Ё», набранные без ошибки (у английских сессий 0); `nil` у записей до фазы 5.
    var yoPresses: Int? = nil
    /// Номер шага в плане урока (`ExerciseSpec.id`, с нуля); `nil` вне курса и у записей до поколения 6.
    /// Нужен, потому что в уроке издания 2 бывает несколько шагов одного вида (фаза 6, §11).
    var stepIndex: Int? = nil
    /// Пункт «Плана на сегодня»: `warmup`, `lesson`, `training`, `text` (фаза 6, §10.1). Пишет подфаза 6c; до неё `nil`.
    var planSlot: String? = nil
    /// Свойства набранного текста (`TextTraits`, битовая маска): 1 — заглавные, 2 — пунктуация, 4 — цифры,
    /// 8 — связный текст. `nil` у записей до поколения 6.
    var textTraits: Int? = nil
    /// Скорость по отрезкам целевого текста (`[SpeedSegment]`, JSON); только у записей курса. `nil` у записей
    /// до поколения 8 и у режимов вне курса (подфаза 8a, §2.1).
    var speedSegments: Data? = nil

    init(mode: String, language: String, lessonId: String?, startedAt: Date, endedAt: Date,
         logicalDay: String, activeSeconds: Double, chars: Int, errorCount: Int, cpm: Double,
         accuracy: Double, completed: Bool, hintLevel: String, maxErrorStreak: Int, wrongKeystrokes: Int,
         exerciseKind: String? = nil, pinkyPresses: Int = 0, pinkyErrors: Int = 0, source: String? = nil,
         fingerPresses: Data? = nil, fingerErrors: Data? = nil, yoPresses: Int? = nil, stepIndex: Int? = nil,
         planSlot: String? = nil, textTraits: Int? = nil, speedSegments: Data? = nil) {
        id = UUID()
        self.mode = mode
        self.language = language
        self.lessonId = lessonId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.logicalDay = logicalDay
        self.activeSeconds = activeSeconds
        self.chars = chars
        self.errorCount = errorCount
        self.cpm = cpm
        self.accuracy = accuracy
        self.completed = completed
        self.hintLevel = hintLevel
        self.maxErrorStreak = maxErrorStreak
        self.wrongKeystrokes = wrongKeystrokes
        self.exerciseKind = exerciseKind
        self.pinkyPresses = pinkyPresses
        self.pinkyErrors = pinkyErrors
        self.source = source
        self.fingerPresses = fingerPresses
        self.fingerErrors = fingerErrors
        self.yoPresses = yoPresses
        self.stepIndex = stepIndex
        self.planSlot = planSlot
        self.textTraits = textTraits
        self.speedSegments = speedSegments
    }

    /// Отрезки скорости; `nil` — их нет или они не читаются.
    var decodedSpeedSegments: [SpeedSegment]? {
        speedSegments.flatMap { try? JSONDecoder().decode([SpeedSegment].self, from: $0) }
    }
}

@Model final class LessonProgress {
    #Unique<LessonProgress>([\.lessonId])
    var lessonId: String
    var language: String
    var attempts: Int = 0
    var bestStars: Int = 0
    var bestCpm: Double = 0
    var bestAccuracy: Double = 0
    var passedAt: Date?

    init(lessonId: String, language: String) {
        self.lessonId = lessonId
        self.language = language
    }
}

@Model final class KeyStat {
    #Unique<KeyStat>([\.language, \.character])
    var language: String
    var character: String
    var keyCode: Int = 0
    var presses: Int = 0
    var errors: Int = 0
    var ewmaMs: Double?
    var recent: [Bool] = []

    init(language: String, character: String) {
        self.language = language
        self.character = character
    }
}

@Model final class BigramStat {
    #Unique<BigramStat>([\.language, \.bigram])
    var language: String
    var bigram: String
    var count: Int = 0
    var errors: Int = 0
    var ewmaMs: Double?
    var recent: [Bool] = []

    init(language: String, bigram: String) {
        self.language = language
        self.bigram = bigram
    }
}

@Model final class DayRecord {
    #Unique<DayRecord>([\.logicalDay])
    var logicalDay: String
    var activeSeconds: Double = 0
    var completedExercises: Int = 0
    var abandonedExercises: Int = 0
    var languages: [String] = []
    /// Дневная цель (секунды), действовавшая в этот день: пишется при каждом сохранении результата, у сегодняшнего
    /// дня — и при смене цели в настройках. Прошлый день считается по ней, поэтому смена цели не меняет прошлые
    /// огоньки. `nil` у дней до поколения схемы 5, пока при запуске их не заполнит текущая цель (`DayGoals`).
    var goalSeconds: Double? = nil

    init(logicalDay: String) {
        self.logicalDay = logicalDay
    }
}

@Model final class CounterRecord {
    #Unique<CounterRecord>([\.name])
    var name: String
    var value: Int = 0

    init(name: String) {
        self.name = name
    }
}

@Model final class AdaptiveState {
    #Unique<AdaptiveState>([\.language])
    var language: String
    var unlockedCount: Int

    init(language: String, unlockedCount: Int) {
        self.language = language
        self.unlockedCount = unlockedCount
    }
}

/// Когда в адаптивной тренировке открылась буква (одна запись на букву; для ачивок фазы 4).
@Model final class AdaptiveUnlock {
    var language: String
    var letter: String
    var unlockedAt: Date

    init(language: String, letter: String, unlockedAt: Date) {
        self.language = language
        self.letter = letter
        self.unlockedAt = unlockedAt
    }
}

@Model final class CustomText {
    var id: UUID
    var title: String
    var body: String
    var language: String
    /// Позиция в тексте (в символах), с которой начнётся следующая порция.
    var offset: Int = 0
    var createdAt: Date

    init(title: String, body: String, language: String, createdAt: Date = Date()) {
        id = UUID()
        self.title = title
        self.body = body
        self.language = language
        self.createdAt = createdAt
    }
}

/// Полученная ачивка (фаза 4, поколение схемы 3). `achievementId` — стабильный id из `AchievementCatalog`;
/// `unlockedAt` — дата события из истории (или момент проверки, если её не установить); `seen` — показана ли
/// пользователю (ачивки, выданные задним числом при первом запуске, сразу просмотрены).
@Model final class AchievementRecord {
    #Unique<AchievementRecord>([\.achievementId])
    var achievementId: String
    var unlockedAt: Date
    var seen: Bool = false

    init(achievementId: String, unlockedAt: Date, seen: Bool = false) {
        self.achievementId = achievementId
        self.unlockedAt = unlockedAt
        self.seen = seen
    }
}

/// Одно получение повторяемой ачивки (поколение схемы 6, спецификация фазы 6 §8.4). Пишет подфаза 6d;
/// в 6a модель только заведена. `occurrence` — ключ получения: логический день, id сессии, этапа или урока,
/// неделя `2026-W44`, месяц `2026-11`. Пара (`achievementId`, `occurrence`) уникальна: повторная проверка
/// ничего не дублирует. `AchievementRecord` не меняется и создаётся при первом получении.
@Model final class AchievementGrant {
    #Unique<AchievementGrant>([\.achievementId, \.occurrence])
    var achievementId: String
    var occurrence: String
    var grantedAt: Date
    /// Значение получения: скорость рекорда, звёзды, ступень, число заходов; `nil` — значения нет.
    var value: Double? = nil
    /// Показано ли получение пользователю (выданные задним числом — сразу просмотрены).
    var seen: Bool = false

    init(achievementId: String, occurrence: String, grantedAt: Date, value: Double? = nil, seen: Bool = false) {
        self.achievementId = achievementId
        self.occurrence = occurrence
        self.grantedAt = grantedAt
        self.value = value
        self.seen = seen
    }
}

/// Результат одного захода игры «Ритм» (поколение схемы 7, решение 9). Рядом с ним заход пишется и как обычная
/// `SessionRecord` (`mode` `rhythm`): время, день и ачивки; здесь — то, чего в сессии нет: очки, оценка, разбор.
/// `judgements` — JSON `[String: Int]` (`RhythmReport.counts`), `report` — JSON `RhythmReport`.
@Model final class RhythmResult {
    var id: UUID
    var language: String
    /// `RhythmNoteMode.rawValue`.
    var mode: String
    /// `RhythmLevelID.rawValue`.
    var level: String
    var bpm: Int
    var startedAt: Date
    var endedAt: Date
    var score: Int
    var accuracy: Double
    var maxCombo: Int
    /// `RhythmGrade.rawValue`: S, A, B, C, D.
    var grade: String
    var cleared: Bool
    var judgements: Data
    var report: Data

    init(language: String, mode: String, level: String, bpm: Int, startedAt: Date, endedAt: Date, score: Int,
         accuracy: Double, maxCombo: Int, grade: String, cleared: Bool, judgements: Data, report: Data) {
        id = UUID()
        self.language = language
        self.mode = mode
        self.level = level
        self.bpm = bpm
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.score = score
        self.accuracy = accuracy
        self.maxCombo = maxCombo
        self.grade = grade
        self.cleared = cleared
        self.judgements = judgements
        self.report = report
    }
}

enum CounterName {
    static let wrongLayoutStarts = "wrongLayoutStarts"
    static let capsLockPresses = "capsLockPresses"

    /// Все счётчики, которые пишет приложение (на них ссылаются ачивки `counter(name:threshold:)`).
    static let all = [wrongLayoutStarts, capsLockPresses]
}
