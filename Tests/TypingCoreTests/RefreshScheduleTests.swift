import Foundation
import Testing
@testable import TypingCore

// Интервальные возвраты «Освежить» (§6.3; решения 7, 8, 8а).

private let day0 = "2027-03-01"
/// Логический день `n` дней после `day0`.
private func d(_ n: Int) -> String { RefreshSchedule.addDays(day0, n)! }

private let lesson = "ru2.s1.01"   // цель 60: ★★ от 48 зн/мин, ★★★ от 60, ★★★★ от 78, ★★★★★ от 90

/// Завершённая попытка проверки урока: `check` или `refresh` на день `day` (`second` — порядок внутри дня).
private func attempt(_ kind: ExerciseKind, day: Int, cpm: Double, accuracy: Double = 1, lessonId: String = lesson,
                     completed: Bool = true, second: Double = 0) -> SessionSummary {
    let key = d(day)
    return SessionSummary(day: key, endedAt: Date(timeIntervalSince1970: Double(RefreshSchedule.dayNumber(key)!) * 86400
                                                  + second),
                          language: .ru, mode: .course, chars: 90, activeSeconds: 60, accuracy: accuracy,
                          completed: completed, lessonId: lessonId, exerciseKind: kind, cpm: cpm)
}

private let two = 50.0, three = 62.0   // скорости ★★ и ★★★ урока с целью 60

private func state(passed: Int? = 0, stars: Int, _ sessions: [SessionSummary], today: Int, target: Int = 60,
                   lessonId: String = lesson) -> RefreshState {
    RefreshSchedule.state(lessonId: lessonId, passedDay: passed.map(d), currentStars: stars, sessions: sessions,
                          targetCpm: target, today: d(today))
}

// MARK: - Ключи дней

@Test func dayKeysAddDaysAcrossMonthsAndLeapYears() {
    #expect(RefreshSchedule.addDays("2027-03-01", 1) == "2027-03-02")
    #expect(RefreshSchedule.addDays("2027-03-01", -1) == "2027-02-28")
    #expect(RefreshSchedule.addDays("2028-02-28", 2) == "2028-03-01")
    #expect(RefreshSchedule.addDays("2026-12-31", 14) == "2027-01-14")
    #expect(RefreshSchedule.dayNumber("1970-01-02") == 1)
    #expect(RefreshSchedule.dayNumber("не день") == nil)
    #expect(RefreshSchedule.dayNumber(d(10))! - RefreshSchedule.dayNumber(d(3))! == 7)
}

// MARK: - Расписание слабо сданного урока (решение 8)

@Test func weakLessonIsDueTheDayAfterPassing() {
    let sessions = [attempt(.check, day: 0, cpm: two)]
    #expect(state(stars: 2, sessions, today: 0) == .waiting(until: d(1), hard: false))
    #expect(state(stars: 2, sessions, today: 1) == .due(since: d(1), hard: false))
    #expect(state(stars: 2, sessions, today: 9) == .due(since: d(1), hard: false))   // не копится
}

@Test func refreshesAtTwoStarsStretchTheIntervals() {
    let first = attempt(.refresh, day: 1, cpm: two)
    #expect(state(stars: 2, [first], today: 1) == .waiting(until: d(4), hard: false))
    #expect(state(stars: 2, [first], today: 4) == .due(since: d(4), hard: false))
    let second = attempt(.refresh, day: 4, cpm: two)
    #expect(state(stars: 2, [first, second], today: 4) == .waiting(until: d(11), hard: false))
    #expect(state(stars: 2, [first, second], today: 11) == .due(since: d(11), hard: false))
    // Третья: урок «трудный» — раз в 14 дней от последней попытки.
    let third = attempt(.refresh, day: 11, cpm: two)
    let all = [first, second, third]
    #expect(state(stars: 2, all, today: 11) == .waiting(until: d(25), hard: true))
    #expect(state(stars: 2, all, today: 24) == .waiting(until: d(25), hard: true))
    #expect(state(stars: 2, all, today: 25) == .due(since: d(25), hard: true))
    #expect(state(stars: 2, all, today: 60) == .due(since: d(25), hard: true))
    // Четвёртая сдвигает срок ещё на 14 дней от неё.
    #expect(state(stars: 2, all + [attempt(.refresh, day: 30, cpm: two)], today: 31) == .waiting(until: d(44), hard: true))
}

@Test func failedRefreshesOnOneDayAreOneAttempt() {
    // Решение пользователя 2026-10-30: повтор сразу после неудачи не отодвигает урок дальше.
    let sessions = [attempt(.refresh, day: 1, cpm: two, second: 1), attempt(.refresh, day: 1, cpm: two, second: 2)]
    #expect(state(stars: 2, sessions, today: 1) == .waiting(until: d(4), hard: false))
    let hard = [1, 1, 4, 4, 4].enumerated().map { attempt(.refresh, day: $1, cpm: two, second: Double($0)) }
    #expect(state(stars: 2, hard, today: 4) == .waiting(until: d(11), hard: false))
}

@Test func refreshBelowPassingCountsAsAnAttemptToo() {
    // Точность 90% — ни одной звезды, но попытка завершена: срок идёт от неё.
    let miss = attempt(.refresh, day: 1, cpm: 90, accuracy: 0.9)
    #expect(state(stars: 2, [miss], today: 2) == .waiting(until: d(4), hard: false))
}

@Test func unfinishedAndOtherKindsDoNotCountAsRefreshes() {
    let sessions = [attempt(.refresh, day: 1, cpm: two, completed: false), attempt(.words, day: 1, cpm: two),
                    attempt(.check, day: 2, cpm: two)]
    #expect(state(stars: 2, sessions, today: 3) == .due(since: d(1), hard: false))
}

@Test func threeStarRefreshOrRecheckClosesTheSchedule() {
    #expect(state(stars: 3, [attempt(.check, day: 0, cpm: two), attempt(.refresh, day: 1, cpm: three)], today: 2) == .closed)
    #expect(state(stars: 3, [attempt(.check, day: 0, cpm: two), attempt(.refresh, day: 1, cpm: two),
                             attempt(.refresh, day: 4, cpm: three)],
                  today: 20) == .closed)
    #expect(state(stars: 3, [attempt(.check, day: 0, cpm: two), attempt(.check, day: 2, cpm: three)], today: 5) == .closed)
    // Закрытый возврат не воскресает после ★★ позже по ходу: лучшее остаётся ★★★ (проверка, не «Освежить»).
    #expect(state(stars: 3, [attempt(.check, day: 0, cpm: two), attempt(.check, day: 2, cpm: three),
                             attempt(.check, day: 6, cpm: two)], today: 9) == .closed)
}

@Test func wellPassedLessonHasNoSchedule() {
    #expect(state(stars: 3, [attempt(.check, day: 0, cpm: three)], today: 9) == .none)
    #expect(state(stars: 5, [], today: 9) == .none)
    // Не засчитан, издание 1 — возвратов нет.
    #expect(state(passed: nil, stars: 0, [attempt(.check, day: 0, cpm: 10, accuracy: 0.5)], today: 9) == .none)
    #expect(state(stars: 2, [attempt(.check, day: 0, cpm: two, lessonId: "ru.1.1")], today: 9, lessonId: "ru.1.1") == .none)
}

@Test func failedRotationRefreshPutsAGoodLessonOnTheWeakSchedule() {
    let check = attempt(.check, day: 0, cpm: three)
    // ★★ на «Освежить» ротации: он сам — d0, срок — на следующий день, звёзды урока прежние.
    let fail = attempt(.refresh, day: 10, cpm: two)
    #expect(state(stars: 3, [check, fail], today: 10) == .waiting(until: d(11), hard: false))
    #expect(state(stars: 3, [check, fail], today: 11) == .due(since: d(11), hard: false))
    // Следующая ★★ — уже попытка: +3 от неё.
    let again = attempt(.refresh, day: 11, cpm: two)
    #expect(state(stars: 3, [check, fail, again], today: 11) == .waiting(until: d(14), hard: false))
    // ★★★ закрывает возврат; новый провал открывает его заново с новой точкой отсчёта.
    let good = attempt(.refresh, day: 14, cpm: three)
    #expect(state(stars: 3, [check, fail, again, good], today: 15) == .closed)
    let relapse = attempt(.refresh, day: 60, cpm: two)
    #expect(state(stars: 3, [check, fail, again, good, relapse], today: 61) == .due(since: d(61), hard: false))
}

@Test func sameDayRefreshesAreNotCountedAsAttemptsAfterD0() {
    let check = attempt(.check, day: 0, cpm: three)
    let sessions = [check, attempt(.refresh, day: 10, cpm: two, second: 1), attempt(.refresh, day: 10, cpm: two, second: 2)]
    #expect(state(stars: 3, sessions, today: 10) == .waiting(until: d(11), hard: false))
}

// MARK: - Возвраты курса и «трудные» буквы

private func course() throws -> Course { try CourseFixtures.ruMini() }

@Test func dueListsRegularBeforeHardAndOldestFirst() throws {
    let c = try course()
    let l1 = "ru2.s1.01", l2 = "ru2.s1.02", l3 = "ru2.s1.03", l4 = "ru2.s1.04"
    // Цели уроков 60, 67, 73, 80: скорость 40 — ★ (до ★★ не хватает), 62 у l4 — ★★★ при 80? нет: берём ★★★ явно.
    var sessions = [l1, l2, l3].map { attempt(.check, day: 0, cpm: 40, lessonId: $0) }
    sessions.append(check(l4, day: 0, ratio: 1.0, in: c))
    // l1 — «трудный» (три «Освежить» на ★★), l2 сдан раньше l3, l4 сдан хорошо.
    sessions += [attempt(.refresh, day: 3, cpm: two, lessonId: l1), attempt(.refresh, day: 6, cpm: two, lessonId: l1),
                 attempt(.refresh, day: 13, cpm: two, lessonId: l1)]
    let passedDays = [l1: d(0), l2: d(-5), l3: d(-2), l4: d(0)]
    let stars = [l1: 2, l2: 1, l3: 1, l4: 3]
    let due = RefreshSchedule.due(course: c, passedDays: passedDays, stars: stars, sessions: sessions, today: d(40))
    #expect(due.map(\.lessonId) == [l2, l3, l1])
    #expect(due.map(\.since) == [d(-4), d(-1), d(27)])
    #expect(RefreshSchedule.due(course: c, passedDays: [:], stars: [:], sessions: [], today: d(40)).isEmpty)
}

@Test func hardLettersComeFromHardLessonsNewKeysOrFocus() throws {
    var json = CourseFixtures.ruMiniJSON
    json = json.replacingOccurrences(of: "{ \"id\": \"ru2.s1.04\", \"title\": \"Повтор\", \"kind\": \"review\" }",
                                     with: "{ \"id\": \"ru2.s1.04\", \"title\": \"Повтор\", \"kind\": \"review\", \"focus\": [\"р\", \"вств\"] }")
    let c = try JSONDecoder().decode(Course.self, from: Data(json.utf8))
    func hardRefreshes(_ id: String) -> [SessionSummary] {
        [attempt(.check, day: 0, cpm: 40, lessonId: id), attempt(.refresh, day: 3, cpm: two, lessonId: id),
         attempt(.refresh, day: 6, cpm: two, lessonId: id), attempt(.refresh, day: 13, cpm: two, lessonId: id)]
    }
    let passed = ["ru2.s1.01": d(0), "ru2.s1.02": d(0), "ru2.s1.04": d(0)]
    let stars = ["ru2.s1.01": 2, "ru2.s1.02": 2, "ru2.s1.04": 2]
    // «Трудные» — 01 (новые «а», «о») и 04 (без новых клавиш: односимвольный focus «р»); 02 — обычный слабый.
    let sessions = hardRefreshes("ru2.s1.01") + hardRefreshes("ru2.s1.04") + [attempt(.check, day: 0, cpm: 40, lessonId: "ru2.s1.02")]
    #expect(RefreshSchedule.hardLetters(course: c, passedDays: passed, stars: stars, sessions: sessions, today: d(14))
        == ["а", "о", "р"])
    // Вес держится и пока срок не наступил (урок «трудный»), но обычные слабые буквы не дают.
    #expect(RefreshSchedule.hardLetters(course: c, passedDays: passed, stars: stars, sessions: sessions, today: d(20))
        == ["а", "о", "р"])
    #expect(RefreshSchedule.hardLetters(course: c, passedDays: passed, stars: stars,
                                        sessions: [attempt(.check, day: 0, cpm: 40, lessonId: "ru2.s1.02")], today: d(14)).isEmpty)
}

// MARK: - Ротация (решение 8а)

private let l1 = "ru2.s1.01", l2 = "ru2.s1.02", l3 = "ru2.s1.03", l4 = "ru2.s1.04"

/// Проверка урока на день `day` со скоростью `ratio` × цель урока.
private func check(_ id: String, day: Int, ratio: Double, in c: Course, kind: ExerciseKind = .check) -> SessionSummary {
    attempt(kind, day: day, cpm: ratio * Double(c.targetCpm(for: id)!), lessonId: id)
}

@Test func rotationStartsWithLessonsBelowFiveStars() throws {
    let c = try course()
    let sessions = [check(l1, day: 0, ratio: 2.0, in: c), check(l2, day: 0, ratio: 1.1, in: c)]
    #expect(RefreshSchedule.rotation(course: c, stars: [l1: 5, l2: 4], sessions: sessions, today: d(20)) == l2)
    #expect(RefreshSchedule.rotation(course: c, stars: [l1: 5], sessions: [sessions[0]], today: d(20)) == l1)
}

@Test func rotationOrdersByTheSmallestSpeedReserve() throws {
    let c = try course()
    let sessions = [check(l1, day: 0, ratio: 1.8, in: c), check(l2, day: 0, ratio: 1.52, in: c),
                    check(l3, day: 0, ratio: 1.8, in: c)]
    #expect(RefreshSchedule.rotation(course: c, stars: [l1: 5, l2: 5, l3: 5], sessions: sessions, today: d(20)) == l2)
    // Запас — лучшая из попыток урока, «Освежить» тоже считается.
    let better = sessions + [check(l2, day: 1, ratio: 2.4, in: c, kind: .refresh)]
    #expect(RefreshSchedule.rotation(course: c, stars: [l1: 5, l2: 5, l3: 5], sessions: better, today: d(20)) == l1)
}

@Test func rotationBreaksTiesByTheLongestUnopenedThenCourseOrder() throws {
    let c = try course()
    let sessions = [check(l1, day: 5, ratio: 1.6, in: c), check(l2, day: 2, ratio: 1.6, in: c),
                    check(l3, day: 2, ratio: 1.6, in: c)]
    #expect(RefreshSchedule.rotation(course: c, stars: [l1: 5, l2: 5, l3: 5], sessions: sessions, today: d(20)) == l2)
}

@Test func rotationNeedsSevenDaysSinceTheLastExercise() throws {
    let c = try course()
    // Последнее упражнение урока — любой шаг, не только проверка.
    let sessions = [check(l1, day: 0, ratio: 1.6, in: c),
                    SessionSummary(day: d(4), endedAt: Date(timeIntervalSince1970: 1_800_000_000), language: .ru,
                                   mode: .course, chars: 50, activeSeconds: 30, accuracy: 1, completed: true,
                                   lessonId: l1, exerciseKind: .words, cpm: 60)]
    #expect(RefreshSchedule.rotation(course: c, stars: [l1: 4], sessions: sessions, today: d(10)) == nil)   // 6 дней
    #expect(RefreshSchedule.rotation(course: c, stars: [l1: 4], sessions: sessions, today: d(11)) == l1)    // 7 дней
}

@Test func rotationSkipsWeakAndUnpassedLessonsAndEmptyCourses() throws {
    let c = try course()
    let sessions = [check(l1, day: 0, ratio: 1.0, in: c), check(l2, day: 0, ratio: 1.0, in: c)]
    #expect(RefreshSchedule.rotation(course: c, stars: [l1: 2, l2: 0], sessions: sessions, today: d(30)) == nil)
    #expect(RefreshSchedule.rotation(course: c, stars: [:], sessions: [], today: d(30)) == nil)
    // Урок, провалившийся на ротации и стоящий на расписании слабых, в ротацию не возвращается.
    let failed = sessions + [check(l1, day: 20, ratio: 0.8, in: c, kind: .refresh)]
    #expect(RefreshSchedule.rotation(course: c, stars: [l1: 3, l2: 3], sessions: failed, today: d(30)) == l2)
}

@Test func recentlyRefreshedLessonGoesLast() throws {
    let c = try course()
    let sessions = [check(l1, day: 0, ratio: 1.0, in: c), check(l2, day: 0, ratio: 1.7, in: c),
                    check(l3, day: 0, ratio: 1.9, in: c),
                    check(l1, day: 20, ratio: 1.5, in: c, kind: .refresh)]   // ротация освежила l1 за 10 дней до today
    let stars = [l1: 4, l2: 5, l3: 5]
    // l1 хуже всех, но освежён недавно: сначала l2 и l3, он — в конце.
    #expect(RefreshSchedule.rotation(course: c, stars: stars, sessions: sessions, today: d(30)) == l2)
    #expect(RefreshSchedule.rotation(course: c, stars: [l1: 4], sessions: sessions, today: d(30)) == l1)
    // Через 28 дней он снова в общей очереди.
    #expect(RefreshSchedule.rotation(course: c, stars: stars, sessions: sessions, today: d(49)) == l1)
}
