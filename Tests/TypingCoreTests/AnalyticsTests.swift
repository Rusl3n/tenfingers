import Foundation
import Testing
@testable import TypingCore

private func session(_ day: String, chars: Int, seconds: Double, accuracy: Double = 1, completed: Bool = true,
                     language: Language = .ru, endedAt: Double = 0, cpm: Double? = nil,
                     kind: ExerciseKind? = nil, errors: Int = 0) -> SessionSummary {
    SessionSummary(day: day, endedAt: Date(timeIntervalSince1970: endedAt), language: language,
                   mode: kind == nil ? .practice : .course, chars: chars, activeSeconds: seconds, accuracy: accuracy,
                   completed: completed, lessonId: kind == nil ? nil : "l1", exerciseKind: kind, cpm: cpm,
                   errorCount: errors)
}

@Test func dailyAggregatesCompletedSessions() {
    let points = Analytics.daily([
        session("2026-10-24", chars: 1000, seconds: 300, accuracy: 1.0),
        session("2026-10-24", chars: 500, seconds: 200, accuracy: 0.97),
        session("2026-10-24", chars: 50, seconds: 40, accuracy: 0.5, completed: false),
        session("2026-10-23", chars: 100, seconds: 60, accuracy: 0.9),
    ], language: nil)
    #expect(points.map(\.day) == ["2026-10-23", "2026-10-24"])
    let day = points[1]
    #expect(abs(day.cpm - 180) < 1e-9)
    #expect(abs(day.accuracy - (1000 * 1.0 + 500 * 0.97) / 1500) < 1e-9)
    #expect(day.seconds == 540)
    #expect(day.sessions == 2)
}

@Test func dailyStoredCpmEqualToCharsPerSecondMatchesDerived() {
    let derived = Analytics.daily([session("d", chars: 600, seconds: 120)], language: nil)[0].cpm
    let stored = Analytics.daily([session("d", chars: 600, seconds: 120, cpm: 600.0 / 120 * 60)], language: nil)[0].cpm
    #expect(abs(derived - 300) < 1e-9 && abs(stored - derived) < 1e-9)
}

@Test func dailyUsesLowerStoredCpm() {
    // Новая формула: первый знак времени не имеет, скорость считается по (chars - 1).
    let stored = 599.0 / 120 * 60
    let point = Analytics.daily([session("d", chars: 600, seconds: 120, cpm: stored)], language: nil)[0]
    #expect(abs(point.cpm - stored) < 1e-9 && point.cpm < 300)
}

@Test func dailyMixedStoredCpmIsSecondsWeightedMean() {
    let point = Analytics.daily([
        session("d", chars: 600, seconds: 100, cpm: 300),
        session("d", chars: 600, seconds: 300, cpm: 100),
        session("d", chars: 600, seconds: 50, completed: false, cpm: 5000),   // брошенная не учитывается
    ], language: nil)[0]
    #expect(abs(point.cpm - (300.0 * 100 + 100.0 * 300) / 400) < 1e-9)
}

@Test func dailyOnlyAbandonedSessionsGivesZeroCpm() {
    let points = Analytics.daily([session("2026-10-24", chars: 50, seconds: 40, completed: false)], language: nil)
    #expect(points.count == 1)
    #expect(points[0].cpm == 0 && points[0].accuracy == 0 && points[0].sessions == 0 && points[0].seconds == 40)
}

@Test func dailyFiltersByLanguage() {
    let list = [session("2026-10-24", chars: 100, seconds: 60, language: .ru),
                session("2026-10-24", chars: 600, seconds: 60, language: .en)]
    #expect(Analytics.daily(list, language: .en)[0].cpm == 600)
    #expect(Analytics.daily(list, language: .ru)[0].cpm == 100)
    #expect(Analytics.daily(list, language: nil)[0].cpm == 350)
}

@Test func trendLinear() throws {
    let t = try #require(Analytics.trend([1, 2, 3]))
    #expect(abs(t.slope - 1) < 1e-9 && abs(t.intercept - 1) < 1e-9)
    #expect(Analytics.trend([5]) == nil)
    #expect(Analytics.trend([]) == nil)
    let flat = try #require(Analytics.trend([4, 4, 4]))
    #expect(flat.slope == 0 && flat.intercept == 4)
}

@Test func totalsByPeriod() {
    let t = Analytics.totals(secondsByDay: ["2026-10-24": 100, "2026-10-20": 50, "2026-10-01": 10, "2026-09-01": 5],
                             today: "2026-10-24")
    #expect(t.today == 100 && t.week == 150 && t.month == 160 && t.all == 165)
}

@Test func totalsWindowBoundaries() {
    let t = Analytics.totals(secondsByDay: ["2026-10-18": 1, "2026-10-17": 2, "2026-09-25": 4, "2026-09-24": 8],
                             today: "2026-10-24")
    #expect(t.week == 1)
    #expect(t.month == 7)
}

@Test func recordsIgnoreShortSessions() {
    let r = Analytics.records([
        session("d", chars: 200, seconds: 1, accuracy: 1, language: .ru),       // слишком короткая
        session("d", chars: 600, seconds: 120, accuracy: 0.9, language: .ru, endedAt: 10),   // 300 cpm, с ошибками
        session("d", chars: 600, seconds: 100, accuracy: 1, language: .ru, endedAt: 20),     // 360 cpm
        session("d", chars: 400, seconds: 100, accuracy: 1, language: .en, endedAt: 30),     // 240 cpm
        session("d", chars: 900, seconds: 10, accuracy: 1, completed: false, language: .en), // не завершена
    ], longestStreak: 5)
    #expect(r.bestCpm[.ru]?.value == 360)
    #expect(r.bestCpm[.ru]?.date == Date(timeIntervalSince1970: 20))
    #expect(r.bestCpm[.en]?.value == 240)
    #expect(r.bestAccuracy[.ru]?.value == 1)
    #expect(r.bestAccuracy[.en]?.value == 1)
    #expect(r.longestStreak == 5)
}

// MARK: Рекорд скорости: проверка урока или текст от 300 знаков, без ошибок

@Test func speedRecordTakesLessonCheckOfAnyLengthWithoutErrors() {
    let r = Analytics.records([
        session("d", chars: 90, seconds: 90.0 * 60 / 224, accuracy: 1, endedAt: 10, kind: .check),
    ], longestStreak: 0)
    #expect(abs((r.bestCpm[.ru]?.value ?? 0) - 224) < 1e-9)
    // Рекорд точности по-прежнему только от 300 знаков.
    #expect(r.bestAccuracy.isEmpty)
}

@Test func speedRecordSkipsCheckWithAnError() {
    let r = Analytics.records([
        session("d", chars: 90, seconds: 24, accuracy: 89.0 / 90, endedAt: 10, kind: .check, errors: 1),
    ], longestStreak: 0)
    #expect(r.bestCpm.isEmpty)
}

@Test func speedRecordSkipsShortNonCheckSteps() {
    let r = Analytics.records([
        session("d", chars: 90, seconds: 20, accuracy: 1, endedAt: 10, kind: .drill),
        session("d", chars: 90, seconds: 20, accuracy: 1, endedAt: 20, kind: .words),
        session("d", chars: 90, seconds: 20, accuracy: 1, endedAt: 30),   // практика
    ], longestStreak: 0)
    #expect(r.bestCpm.isEmpty)
}

@Test func speedRecordTakesLongTextWithoutErrorsButNotWithErrors() {
    let clean = Analytics.records([session("d", chars: 300, seconds: 60, accuracy: 1, endedAt: 10)], longestStreak: 0)
    #expect(clean.bestCpm[.ru]?.value == 300)
    let dirty = Analytics.records([session("d", chars: 600, seconds: 60, accuracy: 0.99, endedAt: 10, errors: 6)],
                                  longestStreak: 0)
    #expect(dirty.bestCpm.isEmpty)
    #expect(dirty.bestAccuracy[.ru]?.value == 0.99)
}

@Test func speedRecordRuleIsSharedWithAchievements() {
    func eligible(completed: Bool = true, kind: ExerciseKind?, chars: Int, accuracy: Double) -> Bool {
        Analytics.isSpeedRecordExercise(completed: completed, kind: kind, chars: chars, accuracy: accuracy)
    }
    #expect(eligible(kind: .check, chars: 90, accuracy: 1))
    #expect(eligible(kind: nil, chars: 300, accuracy: 1))
    #expect(!eligible(kind: .check, chars: 90, accuracy: 0.99))
    #expect(!eligible(kind: .drill, chars: 90, accuracy: 1))
    #expect(!eligible(kind: nil, chars: 299, accuracy: 1))
    #expect(!eligible(completed: false, kind: .check, chars: 90, accuracy: 1))
    let summary = session("d", chars: 90, seconds: 20, accuracy: 1, kind: .check)
    #expect(summary.isSpeedRecordExercise)
    #expect(!session("d", chars: 90, seconds: 20, accuracy: 1, kind: .drill).isSpeedRecordExercise)
}

@Test func recordsStoredCpmEqualToCharsPerSecondMatchesDerived() {
    let r = Analytics.records([session("d", chars: 600, seconds: 100, endedAt: 1, cpm: 600.0 / 100 * 60)],
                              longestStreak: 0)
    #expect(abs((r.bestCpm[.ru]?.value ?? 0) - 360) < 1e-9)
}

@Test func recordsUseLowerStoredCpm() {
    let stored = 599.0 / 100 * 60
    let r = Analytics.records([session("d", chars: 600, seconds: 100, endedAt: 1, cpm: stored)], longestStreak: 0)
    #expect(abs((r.bestCpm[.ru]?.value ?? 0) - stored) < 1e-9)
    #expect((r.bestCpm[.ru]?.value ?? 0) < 360)
}

@Test func recordsTieGoesToEarlier() {
    let r = Analytics.records([
        session("d", chars: 300, seconds: 60, accuracy: 1, endedAt: 50),
        session("d", chars: 300, seconds: 60, accuracy: 1, endedAt: 10),
    ], longestStreak: 0)
    #expect(r.bestAccuracy[.ru]?.date == Date(timeIntervalSince1970: 10))
    #expect(r.bestCpm[.ru]?.date == Date(timeIntervalSince1970: 10))
}

@Test func recordsEmpty() {
    let r = Analytics.records([], longestStreak: 3)
    #expect(r.bestCpm.isEmpty && r.bestAccuracy.isEmpty && r.longestStreak == 3)
}

@Test func fingersMergeKeys() throws {
    let stats = [
        KeyStatSummary(keyCode: 3, presses: 10, errors: 1, ewmaMs: 200),
        KeyStatSummary(keyCode: 5, presses: 30, errors: 3, ewmaMs: 400),
        KeyStatSummary(keyCode: 999, presses: 50, errors: 5, ewmaMs: 100),  // нет пальца
    ]
    let result = Analytics.fingers(stats)
    #expect(result.count == 1)
    let f = try #require(result.first)
    #expect(f.finger == .leftIndex && f.presses == 40)
    #expect(abs(f.errorRate - 0.1) < 1e-9)
    #expect(abs((f.averageMs ?? 0) - 350) < 1e-9)
}

@Test func fingersWithoutTimings() throws {
    let result = Analytics.fingers([KeyStatSummary(keyCode: 3, presses: 4, errors: 0, ewmaMs: nil)])
    #expect(result.first?.averageMs == nil)
}

@Test func heatErrorsNormalizedAndFiltersRare() {
    let stats = [
        KeyStatSummary(keyCode: 1, presses: 10, errors: 1, ewmaMs: nil),   // 0.1
        KeyStatSummary(keyCode: 2, presses: 10, errors: 3, ewmaMs: nil),   // 0.3
        KeyStatSummary(keyCode: 3, presses: 20, errors: 4, ewmaMs: nil),   // 0.2
        KeyStatSummary(keyCode: 4, presses: 4, errors: 4, ewmaMs: nil),    // исключена
    ]
    let heat = Analytics.heat(stats, mode: .errors)
    #expect(heat[4] == nil)
    #expect(abs(heat[1]! - 0) < 1e-9 && abs(heat[2]! - 1) < 1e-9 && abs(heat[3]! - 0.5) < 1e-9)
}

@Test func heatSlownessAndFlat() {
    let slow = Analytics.heat([
        KeyStatSummary(keyCode: 1, presses: 10, errors: 0, ewmaMs: 100),
        KeyStatSummary(keyCode: 2, presses: 10, errors: 0, ewmaMs: 300),
        KeyStatSummary(keyCode: 3, presses: 10, errors: 0, ewmaMs: nil),
    ], mode: .slowness)
    #expect(slow[1] == 0 && slow[2] == 1 && slow[3] == nil)
    let flat = Analytics.heat([KeyStatSummary(keyCode: 1, presses: 10, errors: 2, ewmaMs: 5)], mode: .errors)
    #expect(flat[1] == 0.5)
    #expect(Analytics.heat([], mode: .errors).isEmpty)
}

@Test func dayKeyOffset() {
    #expect(StreakCalculator.dayKey("2026-10-24", offset: -6) == "2026-10-18")
    #expect(StreakCalculator.dayKey("2026-10-24", offset: -29) == "2026-09-25")
    #expect(StreakCalculator.dayKey("2026-03-01", offset: -1) == "2026-02-28")
    #expect(StreakCalculator.dayKey("2026-12-31", offset: 1) == "2027-01-01")
}
