/// Класс пальца по последним 14 дням (§6.4).
public enum FingerClass: Equatable, Sendable { case weak, normal, strong, noData }

/// Оценка одного пальца: нажатия, точность, скорость и класс.
public struct FingerReport: Equatable, Sendable {
    public let finger: Finger
    public let presses: Int
    /// Доля верных нажатий; `nil`, если нажатий нет.
    public let accuracy: Double?
    /// Знаков в минуту по среднему `ewmaMs` клавиш пальца (взвешено по нажатиям); `nil` — нет данных по клавишам.
    public let speedCpm: Double?
    public let kind: FingerClass
}

/// Занятие по пальцу: на точность или на скорость.
public enum FingerDrill: String, Sendable { case accuracy, speed }

/// «Пальцы» (§6.4): оценка пальцев, слабейший и сильнейший, тексты и порции занятий.
public enum FingerTraining {
    /// Окно данных, логических дней.
    public static let days = 14
    /// Меньше нажатий — «нет данных».
    public static let minimumPresses = 50
    /// Слабый палец: точность ниже 97%.
    public static let weakBelow = 0.97
    /// Нет слабых — худший палец, если его точность ниже 99%.
    public static let worstBelow = 0.99
    /// Сильный палец: точность от 99% и не меньше 100 нажатий.
    public static let strongAccuracy = 0.99
    public static let strongMinimumPresses = 100
    /// Цель занятия на скорость — скорость пальца × 1,1.
    public static let speedTargetFactor = 1.1

    /// `presses`/`errors` — нажатия и ошибки пальцев за `days` дней (суммирует приложение); `keyEwma` — буква →
    /// (`ewmaMs`, нажатия); `fingerOf` — буква → палец по истории клавиш (запасом — раскладка); `thresholdMs` — `AdaptiveTrainer.thresholdMs`.
    /// Большой палец не оценивается — в списке его нет. Порядок — как в `Finger.allCases`.
    public static func reports(presses: [Finger: Int], errors: [Finger: Int],
                               keyEwma: [Character: (ms: Double, presses: Int)],
                               fingerOf: [Character: Finger], thresholdMs: Double) -> [FingerReport] {
        Finger.allCases.filter { $0 != .thumb }.map { finger in
            let count = max(0, presses[finger] ?? 0)
            let wrong = min(count, max(0, errors[finger] ?? 0))
            let accuracy = count > 0 ? Double(count - wrong) / Double(count) : nil
            let averageMs = averageMs(of: finger, keyEwma: keyEwma, fingerOf: fingerOf)
            let kind: FingerClass
            if count < minimumPresses {
                kind = .noData
            } else if let accuracy, accuracy < weakBelow {
                kind = .weak
            } else if let accuracy, accuracy >= strongAccuracy, count >= strongMinimumPresses,
                      let averageMs, averageMs <= thresholdMs {
                kind = .strong
            } else {
                kind = .normal
            }
            return FingerReport(finger: finger, presses: count, accuracy: accuracy,
                                speedCpm: averageMs.map { 60_000 / $0 }, kind: kind)
        }
    }

    /// Слабейший: среди слабых — с наименьшей точностью; слабых нет — палец с наименьшей точностью среди имеющих
    /// данные, если она ниже 99%; иначе `nil`. При равенстве — по порядку `Finger.allCases`.
    public static func weakest(_ reports: [FingerReport]) -> Finger? {
        let weak = reports.filter { $0.kind == .weak }
        if let worst = lowestAccuracy(weak) { return worst.finger }
        guard let worst = lowestAccuracy(reports.filter { $0.kind != .noData }),
              let accuracy = worst.accuracy, accuracy < worstBelow else { return nil }
        return worst.finger
    }

    /// Сильнейший: среди сильных — с наибольшей скоростью; при равенстве — по порядку `Finger.allCases`.
    public static func strongest(_ reports: [FingerReport]) -> Finger? {
        var best: FingerReport?
        for report in order(reports) where report.kind == .strong {
            if best == nil || (report.speedCpm ?? 0) > (best?.speedCpm ?? 0) { best = report }
        }
        return best?.finger
    }

    /// Порции занятия: 3×150 знаков (точность) или 4×100 (скорость). `id` порций — с 1. В словах не меньше 40% букв
    /// пальца (из `open`); таких слов меньше 20 — `focusedWords` с упором на буквы пальца.
    /// Цель скорости в `ExerciseSpec` не хранится — её задаёт запуск (`targetCpm(speedCpm:)`).
    public static func portions<G: RandomNumberGenerator>(_ drill: FingerDrill, finger: Finger, open: Set<Character>,
                                                          fingerOf: [Character: Finger], generator: TextGenerator,
                                                          rng: inout G) -> [ExerciseSpec] {
        let (count, length, title) = switch drill {
        case .accuracy: (3, 150, "Точность пальца")
        case .speed: (4, 100, "Скорость пальца")
        }
        let letters = Set(open.filter { fingerOf[$0] == finger })
        // Букв пальца не определить (нет истории клавиш и раскладки): случайные слова — не занятие по пальцу.
        guard !letters.isEmpty else { return [] }
        let pool = generator.focusPool(letters: open)
        return (1...count).map { id in
            let text = generator.fingerWords(letters: open, fingerLetters: letters, length: length, pool: pool,
                                             rng: &rng)
            return ExerciseSpec(id: id, kind: .words, title: title, text: text)
        }
    }

    /// Буква → палец по истории клавиш (`KeyStat.keyCode` каждой буквы, `FingerMap`), без активной раскладки.
    /// Заглавная и строчная — одна клавиша; буквы не из языка и строки без настоящего кода пропускаются. Код 0 —
    /// значение по умолчанию у строк без кода и одновременно клавиша «ф»/«a», поэтому ему верим только для этой буквы.
    /// `fallback` (раскладка) — только для букв, которых в истории нет.
    public static func letterFingers(keys: [(character: String, keyCode: Int, presses: Int)], language: Language,
                                     fallback: [Character: Finger] = [:]) -> [Character: Finger] {
        let aKeyLetter: Character = language == .ru ? "ф" : "a"
        var result: [Character: Finger] = [:]
        // Больше нажатий — раньше: при расхождении кодов у «а»/«А» побеждает основная строка.
        for key in keys.sorted(by: { $0.presses > $1.presses }) {
            let lowered = key.character.lowercased()
            guard lowered.count == 1, let letter = lowered.first, language.letters.contains(letter),
                  result[letter] == nil, let code = UInt16(exactly: key.keyCode),
                  code != 0 || letter == aKeyLetter, let finger = FingerMap.finger(for: code) else { continue }
            result[letter] = finger
        }
        for (letter, finger) in fallback where result[letter] == nil { result[letter] = finger }
        return result
    }

    /// Цель занятия на скорость: скорость пальца × 1,1, округление до целого; без скорости — `nil`.
    public static func targetCpm(speedCpm: Double?) -> Int? {
        speedCpm.map { Int(($0 * speedTargetFactor).rounded()) }
    }

    /// Источник записи: `finger:<Finger.rawValue>:accuracy|speed`.
    public static func source(_ finger: Finger, _ drill: FingerDrill) -> String {
        "finger:\(finger.rawValue):\(drill.rawValue)"
    }

    private static func lowestAccuracy(_ reports: [FingerReport]) -> FingerReport? {
        var best: FingerReport?
        for report in order(reports) {
            guard let accuracy = report.accuracy else { continue }
            if best == nil || accuracy < (best?.accuracy ?? 1) { best = report }
        }
        return best
    }

    private static func order(_ reports: [FingerReport]) -> [FingerReport] {
        reports.sorted { Finger.allCases.firstIndex(of: $0.finger)! < Finger.allCases.firstIndex(of: $1.finger)! }
    }

    private static func averageMs(of finger: Finger, keyEwma: [Character: (ms: Double, presses: Int)],
                                  fingerOf: [Character: Finger]) -> Double? {
        var weighted = 0.0, total = 0
        for (letter, stat) in keyEwma where fingerOf[letter] == finger && stat.presses > 0 && stat.ms > 0 {
            weighted += stat.ms * Double(stat.presses)
            total += stat.presses
        }
        return total > 0 ? weighted / Double(total) : nil
    }
}
