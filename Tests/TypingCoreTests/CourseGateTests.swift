import Testing
@testable import TypingCore

// Гейт этапов, экстерн и «Продолжить» издания 2 (спецификация фазы 6, §3; решения 13, 14).

@Test func stageGateAndExam() throws {
    let c = try CourseFixtures.ruMini()
    #expect(c.isUnlocked("ru2.s1.01", passed: []) && !c.isUnlocked("ru2.s1.02", passed: []))
    #expect(c.isUnlocked("ru2.s1.check", passed: []))                         // экстерн
    #expect(!c.isUnlocked("ru2.s2.01", passed: [], checkStars: ["ru2.s1.check": 1]))
    #expect(c.isUnlocked("ru2.s2.01", passed: ["ru2.s1.check"], checkStars: ["ru2.s1.check": 2]))
    #expect(c.isUnlocked("ru2.s2.check", passed: [], checkStars: ["ru2.s1.check": 2]))
    #expect(!c.isUnlocked("ru2.s2.02", passed: [], checkStars: ["ru2.s1.check": 2]))
}

/// Этап сдан экстерном (проверка набрала порог): пропущенные уроки этого этапа открыты все, а не только первый.
/// Ниже порога — прежний порядок; следующий этап по-прежнему идёт по порядку; издание 1 не меняется.
@Test func stageTakenByExternUnlocksAllItsLessons() throws {
    let c = try CourseFixtures.ruMini()
    let s1 = c.stages[0].lessons.map(\.id)
    #expect(s1.count > 2)
    // Порог этапа 1 (★★) взят, прочих уроков нет в `passed`: открыты все.
    for id in s1 { #expect(c.isUnlocked(id, passed: [], checkStars: ["ru2.s1.check": 2]), "\(id)") }
    #expect(c.isUnlocked("ru2.s1.check", passed: ["ru2.s1.check"], checkStars: ["ru2.s1.check": 3]))
    // ★ — порога нет: только первый урок и проверка, остальные по порядку.
    let below = ["ru2.s1.check": 1]
    #expect(c.isUnlocked(s1[0], passed: [], checkStars: below) && c.isUnlocked("ru2.s1.check", passed: [], checkStars: below))
    #expect(!c.isUnlocked(s1[1], passed: [], checkStars: below) && !c.isUnlocked(s1[2], passed: [s1[0]], checkStars: below))
    #expect(c.isUnlocked(s1[1], passed: [s1[0]], checkStars: below))
    // Порог этапа 1 не открывает уроки этапа 2 и закрытый этап 3.
    #expect(!c.isUnlocked("ru2.s2.02", passed: [], checkStars: ["ru2.s1.check": 2]))
    #expect(c.isUnlocked("ru2.s2.01", passed: [], checkStars: ["ru2.s1.check": 2]))
    // Этап 2 сдан — открыты его уроки.
    #expect(c.isUnlocked("ru2.s2.02", passed: [], checkStars: ["ru2.s1.check": 2, "ru2.s2.check": 3]))
    // Порог этапа 2 — ★★★: ★★ не считается.
    #expect(!c.isUnlocked("ru2.s2.02", passed: [], checkStars: ["ru2.s1.check": 2, "ru2.s2.check": 2]))
    // Издание 1: звёзды проверок ни на что не влияют.
    let legacy = try #require(try CourseCatalog.legacy(.ru))
    #expect(!legacy.isUnlocked("ru.1.3", passed: ["ru.1.1"], checkStars: ["ru.1.check": 3]))
}

@Test func continueTargetPrefersCurrentStage() throws {
    let c = try CourseFixtures.ruMini()
    let s1 = Set(c.stages[0].lessons.map(\.id)), s2 = Set(c.stages[1].lessons.map(\.id))
    #expect(c.continueTarget(passed: [], checkStars: [:]) == .lesson(c.lessons[0]))
    #expect(c.continueTarget(passed: s1, checkStars: ["ru2.s1.check": 1]) == .retakeCheck(c.stages[0].lessons[4]))
    #expect(c.continueTarget(passed: s1, checkStars: ["ru2.s1.check": 2]) == .lesson(c.stages[1].lessons[0]))
    // Экстерн: этап 1 сдан одной проверкой — дальше этап 2, а не урок 1.
    #expect(c.continueTarget(passed: ["ru2.s1.check"], checkStars: ["ru2.s1.check": 2]) == .lesson(c.stages[1].lessons[0]))
    let stars = ["ru2.s1.check": 2, "ru2.s2.check": 3]
    #expect(c.continueTarget(passed: s2.union(["ru2.s1.check"]), checkStars: stars) == .lesson(c.lessons[0]))
    #expect(c.continueTarget(passed: s1.union(s2), checkStars: stars) == nil)
    #expect(c.isCompleted(passed: s1.union(s2), checkStars: stars))
    #expect(!c.isCompleted(passed: s1.union(s2), checkStars: ["ru2.s1.check": 2, "ru2.s2.check": 2]))
    #expect(!c.isCompleted(passed: s2.union(["ru2.s1.check"]), checkStars: stars))
}

@Test func checkStarsComeFromBestCompletedCheck() throws {
    let c = try CourseFixtures.ruMini()
    func s(_ id: String, _ kind: ExerciseKind, _ cpm: Double, _ acc: Double, completed: Bool = true) -> SessionSummary {
        SessionSummary(day: "2027-01-10", endedAt: .now, language: .ru, mode: .course, chars: 60, activeSeconds: 60,
                       accuracy: acc, completed: completed, lessonId: id, exerciseKind: kind, cpm: cpm)
    }
    let stars = CourseGate.checkStars(course: c, sessions: [
        s("ru2.s1.check", .check, 70, 0.97),            // 0,8·80 = 64 → ★★
        s("ru2.s1.check", .check, 200, 1, completed: false),
        s("ru2.s1.check", .words, 200, 1),
        s("ru2.s1.01", .check, 200, 1),                 // не проверка этапа
    ])
    #expect(stars == ["ru2.s1.check": 2])
}

/// Звёзды проверки пишутся только у проверки этапа: у обычного урока карта `checkStars` не растёт.
@Test func withAttemptRecordsCheckStarsOnlyForAStageCheck() throws {
    let course = try CourseFixtures.ruMini()
    let regular = CourseGate.withAttempt(course: course, lessonId: "ru2.s1.03", stars: 3, passed: [], checkStars: [:])
    #expect(regular.passed == ["ru2.s1.03"])
    #expect(regular.checkStars.isEmpty)
    let check = CourseGate.withAttempt(course: course, lessonId: "ru2.s1.check", stars: 1, passed: [],
                                       checkStars: ["ru2.s1.check": 2])
    #expect(check.checkStars == ["ru2.s1.check": 2])
    #expect(check.passed == ["ru2.s1.check"])
    let better = CourseGate.withAttempt(course: course, lessonId: "ru2.s1.check", stars: 3, passed: [],
                                        checkStars: ["ru2.s1.check": 2])
    #expect(better.checkStars == ["ru2.s1.check": 3])
    let notPassed = CourseGate.withAttempt(course: course, lessonId: "ru2.s1.check", stars: 0, passed: [], checkStars: [:])
    #expect(notPassed.passed.isEmpty)
}

/// Общий отбор попыток проверки: завершённые шаги `check` нужного урока со звёздами по цели урока.
@Test func scoredChecksKeepOnlyCompletedCheckStepsOfThatLesson() throws {
    let c = try CourseFixtures.ruMini()
    func s(_ id: String, _ kind: ExerciseKind, _ cpm: Double, completed: Bool = true) -> SessionSummary {
        SessionSummary(day: "2027-01-10", endedAt: .now, language: .ru, mode: .course, chars: 60, activeSeconds: 60,
                       accuracy: 1, completed: completed, lessonId: id, exerciseKind: kind, cpm: cpm)
    }
    let sessions = [s("ru2.s1.check", .check, 40), s("ru2.s1.check", .check, 90), s("ru2.s1.check", .words, 90),
                    s("ru2.s1.check", .check, 90, completed: false), s("ru2.s2.check", .check, 90)]
    let scored = CourseGate.scoredChecks(course: c, checkLessonId: "ru2.s1.check", sessions: sessions)
    #expect(scored.count == 2)
    #expect(scored.map(\.speed) == [40, 90])
    #expect(try #require(scored.last).stars > #require(scored.first).stars)
    #expect(CourseGate.scoredChecks(course: c, checkLessonId: "нет такого", sessions: sessions).isEmpty)
}

/// Издание 1: гейта этапов нет, «Продолжить» — первый незасчитанный урок, курс пройден — все уроки засчитаны.
@Test func editionOneKeepsSequentialRules() throws {
    let c = try #require(try CourseCatalog.legacy(.ru))
    #expect(c.isStageOpen(3, checkStars: [:]))
    #expect(c.isUnlocked("ru.1.2", passed: ["ru.1.1"]) && !c.isUnlocked("ru.1.check", passed: []))
    #expect(c.continueTarget(passed: ["ru.1.1"], checkStars: [:]) == .lesson(c.lessons[1]))
    #expect(c.isCompleted(passed: Set(c.lessons.map(\.id)), checkStars: [:]))
}
