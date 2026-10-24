import Testing
@testable import TypingCore

@Test(arguments: Language.allCases)
func courseLoadsAndCoversWholeAlphabet(language: Language) throws {
    let course = try CourseCatalog.load(language)
    #expect(course.language == language)
    #expect(course.stages.count == 5)
    let taught = Set(course.lessons.flatMap(\.newCharacters))
    #expect(language.letters.isSubset(of: taught))
    #expect(Set("0123456789").isSubset(of: taught))
    #expect(Set(course.lessons.map(\.id)).count == course.lessons.count)
}

@Test func contextAccumulatesAllowedCharacters() throws {
    let course = try CourseCatalog.load(.ru)
    let ctx = try #require(course.context(for: "ru.1.2"))
    #expect(ctx.allowed == Set("аовл "))
    #expect(!ctx.capitals)
    #expect(ctx.targetCpm == 60)
    #expect(ctx.hint == .full)
}

@Test func capitalsAndCheckHintCarryOver() throws {
    let course = try CourseCatalog.load(.ru)
    #expect(course.context(for: "ru.4.3")?.capitals == true)
    #expect(course.context(for: "ru.4.1")?.capitals == false)
    #expect(course.context(for: "ru.2.check")?.hint == .hidden)
    #expect(course.context(for: "ru.3.1")?.hint == .onError)
}

@Test func unlockingFollowsOrder() throws {
    let course = try CourseCatalog.load(.ru)
    #expect(course.isUnlocked("ru.1.1", passed: []))
    #expect(!course.isUnlocked("ru.1.2", passed: []))
    #expect(course.isUnlocked("ru.1.2", passed: ["ru.1.1"]))
    #expect(course.nextLesson(passed: ["ru.1.1"])?.id == "ru.1.2")
    #expect(course.completion(passed: []) == 0)
}

@Test func starsDependOnAccuracyAndSpeed() {
    #expect(LessonScoring.stars(cpm: 200, accuracy: 0.95, targetCpm: 60) == 0)
    #expect(LessonScoring.stars(cpm: 59, accuracy: 0.96, targetCpm: 60) == 1)
    #expect(LessonScoring.stars(cpm: 60, accuracy: 0.98, targetCpm: 60) == 2)
    #expect(LessonScoring.stars(cpm: 78, accuracy: 0.995, targetCpm: 60) == 3)
    #expect(LessonScoring.stars(cpm: 78, accuracy: 1, targetCpm: 60) == 3)
}

@Test func fastButInaccurateEarnsFewerStars() {
    // Скорость вдвое выше цели не спасает точность ниже 98%: только одна звезда.
    #expect(LessonScoring.stars(cpm: 120, accuracy: 0.97, targetCpm: 60) == 1)
    // 99% при скорости ×1,3 — две звезды: для трёх нужно 99,5%.
    #expect(LessonScoring.stars(cpm: 78, accuracy: 0.99, targetCpm: 60) == 2)
    // Точность 100%, но медленнее цели — одна звезда.
    #expect(LessonScoring.stars(cpm: 59, accuracy: 1, targetCpm: 60) == 1)
}

@Test func nextStarHintIsNilWithoutPassOrWithThreeStars() {
    #expect(LessonScoring.nextStarHint(cpm: 200, accuracy: 0.95, targetCpm: 60) == nil)
    #expect(LessonScoring.nextStarHint(cpm: 78, accuracy: 0.995, targetCpm: 60) == nil)
}

@Test func nextStarHintForSecondStarNamesMissingConditions() throws {
    // Медленно, но точно: нужна только скорость.
    let slow = try #require(LessonScoring.nextStarHint(cpm: 52, accuracy: 0.99, targetCpm: 60))
    #expect(slow.needCpm == 60)
    #expect(slow.needAccuracy == nil)
    // Быстро, но с ошибками: нужна только точность.
    let sloppy = try #require(LessonScoring.nextStarHint(cpm: 120, accuracy: 0.97, targetCpm: 60))
    #expect(sloppy.needCpm == nil)
    #expect(sloppy.needAccuracy == LessonScoring.twoStarAccuracy)
    // Не хватает обоих условий.
    let both = try #require(LessonScoring.nextStarHint(cpm: 59, accuracy: 0.96, targetCpm: 60))
    #expect(both.needCpm == 60)
    #expect(both.needAccuracy == 0.98)
}

@Test func nextStarHintForThirdStarUsesThreeStarThresholds() throws {
    let accurateEnough = try #require(LessonScoring.nextStarHint(cpm: 70, accuracy: 0.999, targetCpm: 60))
    #expect(accurateEnough.needCpm == 78)
    #expect(accurateEnough.needAccuracy == nil)
    let fastEnough = try #require(LessonScoring.nextStarHint(cpm: 80, accuracy: 0.989, targetCpm: 60))
    #expect(fastEnough.needCpm == nil)
    #expect(fastEnough.needAccuracy == LessonScoring.threeStarAccuracy)
    let both = try #require(LessonScoring.nextStarHint(cpm: 60, accuracy: 0.98, targetCpm: 60))
    #expect(both.needCpm == 78)
    #expect(both.needAccuracy == 0.995)
}

@Test func nextStarHintMatchesStars() {
    // Выполнив подсказку, получаем следующую звезду.
    for cpm in stride(from: 30.0, through: 120, by: 7) {
        for accuracy in [0.96, 0.97, 0.98, 0.985, 0.99, 0.995, 1] {
            let stars = LessonScoring.stars(cpm: cpm, accuracy: accuracy, targetCpm: 60)
            guard let hint = LessonScoring.nextStarHint(cpm: cpm, accuracy: accuracy, targetCpm: 60) else {
                #expect(stars == 0 || stars == 3)
                continue
            }
            #expect(hint.needCpm != nil || hint.needAccuracy != nil)
            let improved = LessonScoring.stars(cpm: hint.needCpm ?? cpm, accuracy: hint.needAccuracy ?? accuracy,
                                               targetCpm: 60)
            #expect(improved == stars + 1, "cpm \(cpm), accuracy \(accuracy)")
        }
    }
}

@Test(arguments: Language.allCases)
func everyNewKeyIsExactlyOneCharacter(language: Language) throws {
    let course = try CourseCatalog.load(language)
    for lesson in course.lessons {
        for key in lesson.newKeys {
            #expect(key.count == 1, "\(lesson.id): «\(key)» — не один символ")
        }
    }
}
