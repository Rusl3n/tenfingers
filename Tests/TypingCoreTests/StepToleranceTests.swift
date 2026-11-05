import Testing
@testable import TypingCore

@Test func toleranceLimitByLength() {
    #expect(StepTolerance.limit(length: 30) == 3)
    #expect(StepTolerance.limit(length: 74) == 3)
    #expect(StepTolerance.limit(length: 100) == 4)
    #expect(StepTolerance.limit(length: 200) == 8)
    #expect(StepTolerance.limit(length: 500) == 20)
}

@Test func toleranceAppliesOnlyToRegularSteps() {
    #expect(!StepTolerance.applies(kind: .check, lessonKind: .keys))
    #expect(!StepTolerance.applies(kind: .refresh, lessonKind: .keys))
    #expect(!StepTolerance.applies(kind: .words, lessonKind: .stageCheck))
    #expect(!StepTolerance.applies(kind: .drill, lessonKind: .stageCheck))
    #expect(StepTolerance.applies(kind: .words, lessonKind: .keys))
    #expect(StepTolerance.applies(kind: .sentences, lessonKind: .text))
}

@Test func tolerancePassedIsInclusive() {
    #expect(StepTolerance.passed(errorCount: 4, length: 100))
    #expect(!StepTolerance.passed(errorCount: 5, length: 100))
    #expect(StepTolerance.passed(errorCount: 0, length: 10))
}
