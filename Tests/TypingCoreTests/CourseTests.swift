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

@Test(arguments: Language.allCases)
func everyNewKeyIsExactlyOneCharacter(language: Language) throws {
    let course = try CourseCatalog.load(language)
    for lesson in course.lessons {
        for key in lesson.newKeys {
            #expect(key.count == 1, "\(lesson.id): «\(key)» — не один символ")
        }
    }
}
