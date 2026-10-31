import Foundation

// Интервальные возвраты «Освежить» (спецификация фазы 6, §6.3; решения 7, 8, 8а фазы 6c).

/// Где урок на расписании возвратов. Ключи дней — логические (`LogicalDay`).
public enum RefreshState: Equatable, Sendable {
    /// Возвратов нет: урок сдан не слабо, издание 1 или урок не засчитан.
    case none
    /// Возврат наступил с дня `since`; `hard` — урок «трудный» (возвращается раз в 14 дней).
    case due(since: String, hard: Bool)
    /// Возврат ещё не наступил, срок — день `until`.
    case waiting(until: String, hard: Bool)
    /// Урок был на расписании слабых и позже получил ★★★ и выше.
    case closed
}

public enum RefreshSchedule {
    /// Слабо сдан — не выше этих звёзд; ★★★ и выше закрывают возврат.
    static let weakStars = 2
    static let goodStars = 3
    /// Через сколько дней после попытки срок: после d0 — 1, после первой — 3, после второй — 7; дальше — 14.
    static let intervals = [1, 3, 7]
    static let hardInterval = 14
    /// Ротация: урок не открывался столько дней; освежённый ротацией за столько дней уходит в конец очереди.
    static let rotationIdleDays = 7
    static let rotationCooldownDays = 28

    // MARK: - Ключи дней

    /// Номер дня (дней от 1970-01-01) по ключу `гггг-мм-дд`; `nil` — не ключ дня.
    public static func dayNumber(_ key: String) -> Int? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        // Гражданский календарь без `Calendar`: ключ — календарная дата, часовой пояс не влияет.
        let (y, m, d) = (parts[1] <= 2 ? parts[0] - 1 : parts[0], parts[1], parts[2])
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Ключ дня по номеру дня (обратное к `dayNumber`).
    static func dayKey(_ number: Int) -> String {
        let z = number + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
        func pad(_ value: Int, _ width: Int) -> String {
            String(repeating: "0", count: max(0, width - String(value).count)) + String(value)
        }
        return pad(year, 4) + "-" + pad(month, 2) + "-" + pad(day, 2)
    }

    /// Ключ дня через `days` дней (может быть отрицательным); `nil` — `key` не ключ дня.
    public static func addDays(_ key: String, _ days: Int) -> String? {
        dayNumber(key).map { dayKey($0 + days) }
    }

    // MARK: - Расписание слабых

    /// Попытка проверки урока: `check` или `refresh`.
    private struct Attempt {
        let day: String
        let isRefresh: Bool
        let stars: Int
    }

    /// Состояние урока на `today` (ключи логических дней). `sessions` — сессии этого урока.
    ///
    /// Урок на расписании слабых, если сдан на ★★ или ниже (d0 — день `passedDay`) или если «Освежить» на ★★ и ниже
    /// последовало за проверкой на ★★★ и выше — провал ротации (d0 — день этого «Освежить»; сам он не попытка).
    /// n — число «Освежить» на ★★ и ниже после d0: срок d0 + 1, затем последняя попытка + 3, + 7, а с n ≥ 3 урок
    /// «трудный» и возвращается раз в 14 дней. Любая проверка или «Освежить» на ★★★ и выше закрывает возврат.
    /// Звёзды попытки — `LessonScoring.stars` с `targetCpm`; `currentStars` нужны только уроку без попыток в истории.
    public static func state(lessonId: String, passedDay: String?, currentStars: Int, sessions: [SessionSummary],
                             targetCpm: Int, today: String) -> RefreshState {
        guard CourseCatalog.edition(ofLessonId: lessonId) >= 2, let passedDay, dayNumber(passedDay) != nil,
              dayNumber(today) != nil else { return .none }
        let attempts = sessions.enumerated().filter { _, session in
            session.completed && session.lessonId == lessonId && (session.exerciseKind?.isLessonCheck ?? false)
        }.sorted { ($0.element.endedAt, $0.offset) < ($1.element.endedAt, $1.offset) }.map { _, session in
            Attempt(day: session.day, isRefresh: session.exerciseKind == .refresh,
                    stars: LessonScoring.stars(cpm: session.speed, accuracy: session.accuracy, targetCpm: targetCpm))
        }
        // Сдан слабо — по первой засчитанной проверке («Освежить» бывает только после зачёта); проверок нет —
        // по звёздам урока.
        var scheduled = (attempts.first { !$0.isRefresh && $0.stars >= 1 }?.stars ?? currentStars) <= weakStars
        var startDay = passedDay, failures: [String] = [], closed = false
        for attempt in attempts {
            if attempt.stars >= goodStars {
                closed = closed || scheduled
                scheduled = false
                failures = []
            } else if attempt.isRefresh {
                if !scheduled {
                    scheduled = true
                    startDay = attempt.day
                    failures = []
                } else if attempt.day > startDay, failures.last != attempt.day {
                    // Несколько попыток в один день — одна (решение пользователя 2026-10-30).
                    failures.append(attempt.day)
                }
            }
        }
        guard scheduled else { return closed ? .closed : .none }
        let hard = failures.count >= intervals.count
        let (base, interval) = failures.last.map { ($0, hard ? hardInterval : intervals[failures.count]) }
            ?? (startDay, intervals[0])
        guard let dueDay = addDays(base, interval) else { return .none }
        return today >= dueDay ? .due(since: dueDay, hard: hard) : .waiting(until: dueDay, hard: hard)
    }

    /// Состояния уроков издания 2 курса в порядке курса; у уроков без возвратов — `.none`.
    private static func states(course: Course, passedDays: [String: String], stars: [String: Int],
                               sessions: [SessionSummary], today: String) -> [(index: Int, lesson: Lesson, state: RefreshState)] {
        guard course.edition >= 2 else { return [] }
        let byLesson = Dictionary(grouping: sessions.filter { $0.lessonId != nil }) { $0.lessonId! }
        return course.lessons.enumerated().compactMap { index, lesson in
            guard let target = course.targetCpm(for: lesson.id) else { return nil }
            let state = state(lessonId: lesson.id, passedDay: passedDays[lesson.id], currentStars: stars[lesson.id] ?? 0,
                              sessions: byLesson[lesson.id] ?? [], targetCpm: target, today: today)
            return (index, lesson, state)
        }
    }

    /// Все наступившие возвраты курса: обычные, потом «трудные», внутри — самые старые первыми
    /// (при равном сроке — в порядке курса).
    public static func due(course: Course, passedDays: [String: String], stars: [String: Int],
                           sessions: [SessionSummary], today: String) -> [(lessonId: String, since: String)] {
        var due: [(index: Int, lessonId: String, since: String, hard: Bool)] = []
        for (index, lesson, state) in states(course: course, passedDays: passedDays, stars: stars,
                                             sessions: sessions, today: today) {
            if case let .due(since, hard) = state { due.append((index, lesson.id, since, hard)) }
        }
        return due.sorted { lhs, rhs in
            if lhs.hard != rhs.hard { return !lhs.hard }
            return (lhs.since, lhs.index) < (rhs.since, rhs.index)
        }.map { ($0.lessonId, $0.since) }
    }

    /// Буквы «трудных» уроков (решение 8): новые клавиши урока, а у урока без новых клавиш — односимвольный `focus`.
    /// «Трудный» — и пока срок возврата не наступил.
    public static func hardLetters(course: Course, passedDays: [String: String], stars: [String: Int],
                                   sessions: [SessionSummary], today: String) -> Set<Character> {
        var letters = Set<Character>()
        for (_, lesson, state) in states(course: course, passedDays: passedDays, stars: stars,
                                         sessions: sessions, today: today) {
            switch state {
            case .due(_, true), .waiting(_, true):
                let keys = lesson.newCharacters
                letters.formUnion(keys.isEmpty
                                  ? (lesson.focus ?? []).filter { $0.count == 1 }.compactMap { $0.lowercased().first }
                                  : keys)
            default: break
            }
        }
        return letters
    }

    // MARK: - Ротация

    /// Урок ротации (решение 8а): ≥ ★★★, не открывался ≥ 7 дней; сначала ниже ★★★★★; внутри — самый медленный
    /// относительно цели (лучшая скорость проверки урока, `check` или `refresh`, делённая на цель; попыток нет —
    /// запас 0); при равенстве — дольше не открывавшийся, потом раньше в курсе. Освежённые ротацией за 28 дней
    /// (есть завершённый `refresh`) — в конце очереди. Уроки на расписании слабых не берутся; `nil` — кандидатов нет.
    public static func rotation(course: Course, stars: [String: Int], sessions: [SessionSummary],
                                today: String) -> String? {
        guard course.edition >= 2, let todayNumber = dayNumber(today) else { return nil }
        let byLesson = Dictionary(grouping: sessions.filter { $0.completed && $0.lessonId != nil }) { $0.lessonId! }
        var candidates: [(key: [Double], id: String)] = []
        for (index, lesson) in course.lessons.enumerated() {
            guard let lessonStars = stars[lesson.id], lessonStars >= goodStars,
                  let target = course.targetCpm(for: lesson.id) else { continue }
            let done = byLesson[lesson.id] ?? []
            let lastDay = done.compactMap { dayNumber($0.day) }.max()
            guard lastDay.map({ todayNumber - $0 >= rotationIdleDays }) ?? true else { continue }
            // Урок на расписании слабых (провал ротации) — у него свой возврат; d0 для урока ≥ ★★★ не нужен.
            switch state(lessonId: lesson.id, passedDay: today, currentStars: lessonStars, sessions: done,
                         targetCpm: target, today: today) {
            case .due, .waiting: continue
            default: break
            }
            let best = done.filter { $0.exerciseKind?.isLessonCheck ?? false }.map(\.speed).max()
            let recentlyRefreshed = done.contains {
                $0.exerciseKind == .refresh && (dayNumber($0.day).map { todayNumber - $0 < rotationCooldownDays } ?? false)
            }
            candidates.append(([recentlyRefreshed ? 1 : 0, lessonStars >= LessonScoring.maxStars ? 1 : 0,
                                (best ?? 0) / Double(target), Double(lastDay ?? Int.min), Double(index)], lesson.id))
        }
        return candidates.min { $0.key.lexicographicallyPrecedes($1.key) }?.id
    }
}
