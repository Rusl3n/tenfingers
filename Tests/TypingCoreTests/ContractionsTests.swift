import Testing
@testable import TypingCore

@Test func englishContractionsAreLowercaseWithApostrophe() {
    #expect(Contractions.english.contains("don't"))
    #expect(Contractions.english.contains("i'm"))
    #expect(Contractions.english.contains("it's"))
    #expect(Contractions.english.allSatisfy { $0 == $0.lowercased() && $0.contains("'") && !$0.contains("\u{2019}") })
}

@Test func apostropheIsKnownFromItsLessonOnward() throws {
    let course = try CourseCatalog.load(.en)
    let ids = course.lessons.map(\.id)
    let first = try #require(course.lessons.firstIndex { $0.newCharacters.contains("'") })
    #expect(!Contractions.apostropheKnown(courses: [course], lessonIds: []))
    #expect(!Contractions.apostropheKnown(courses: [course], lessonIds: Set(ids[..<first])))
    #expect(Contractions.apostropheKnown(courses: [course], lessonIds: [ids[first]]))
    #expect(Contractions.apostropheKnown(courses: [course], lessonIds: [ids[first + 1]]))
}

@Test func russianCourseNeverKnowsApostrophe() throws {
    let course = try CourseCatalog.load(.ru)
    #expect(!Contractions.apostropheKnown(courses: [course], lessonIds: Set(course.lessons.map(\.id))))
}

@Test func typographicApostropheCountsAsPlainInWords() {
    let hits = ErrorWordTracker.hits(text: "don\u{2019}t", errorPositions: [3], vocabulary: ["don't"])
    #expect(hits == [WordHit(text: "don't", isPhrase: false, hadError: true)])
}
