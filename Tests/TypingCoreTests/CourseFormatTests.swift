import Testing
@testable import TypingCore

// Формат курса издания 2 (спецификация фазы 6, §2.6) и чтение издания 1 тем же декодером.

@Test func legacyCourseDecodesAsEditionOne() throws {
    let course = try #require(try CourseCatalog.legacy(.ru))
    #expect(course.edition == 1 && course.rows == nil)
    let check = try #require(course.lessons.first { $0.id == "ru.1.check" })
    #expect(check.resolvedKind == .stageCheck && course.lessons[0].resolvedKind == .keys)
    #expect(course.targetCpm(for: "ru.2.3") == 90 && course.targetCpm(for: "ru.2.check") == 90)
}

@Test func editionTwoFixtureDecodes() throws {
    let course = try CourseFixtures.ruMini()
    #expect(course.edition == 2 && course.rows?.home == "фывапролджэ")
    #expect(course.stages[0].gate == 2 && course.stages[1].gate == 3)
    #expect(course.stages[0].lengths?.length(for: .drill) == 30)
    #expect(course.stages[0].lengths?.length(for: .sprint) == 100)       // запасная
    #expect(course.stages[0].lengths?.length(for: .text) == 60)          // text → phrases
    #expect(course.stages[1].lengths?.length(for: .rowWords) == 100)
    #expect(course.lessons.first { $0.id == "ru2.s1.03" }?.rows == [.home])
    #expect(course.lessons.first { $0.id == "ru2.s1.04" }?.newKeys == [])
}

@Test func lessonTargetsFollowLinearRule() throws {
    let c = try CourseFixtures.ruMini()
    #expect(["ru2.s1.01", "ru2.s1.02", "ru2.s1.03", "ru2.s1.04", "ru2.s1.check"].map { c.targetCpm(for: $0) }
            == [60, 70, 80, 80, 80])
    #expect(["ru2.s2.01", "ru2.s2.02", "ru2.s2.03", "ru2.s2.04", "ru2.s2.check"].map { c.targetCpm(for: $0) }
            == [90, 110, 110, 100, 110])
    #expect(c.context(for: "ru2.s2.03")?.targetCpm == 110)
}

@Test func contextIntersectsRowsAndTracksNewKeys() throws {
    let c = try CourseFixtures.ruMini()
    let ctx = try #require(c.context(for: "ru2.s2.03"))
    #expect(ctx.rows[.top] == ["к", "е"] && ctx.rows[.home] == ["а", "о", "в", "л"])
    #expect(ctx.stageNewKeys == ["к", "е"] && ctx.introducedKeys == ["а", "о", "в", "л", "к", "е"])
    #expect(ctx.stageNumber == 2 && ctx.edition == 2 && ctx.language == .ru)
}

@Test func catalogKnowsEditionById() {
    #expect(CourseCatalog.edition(ofLessonId: "ru2.s1.01") == 2 && CourseCatalog.edition(ofLessonId: "en2.s7.check") == 2)
    #expect(CourseCatalog.edition(ofLessonId: "ru.1.1") == 1 && CourseCatalog.edition(ofLessonId: "en.5.check") == 1)
}
