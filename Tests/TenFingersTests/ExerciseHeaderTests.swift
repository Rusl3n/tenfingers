import Testing
@testable import TenFingers

/// В шапке упражнения проценты показываются только вне курса: в уроках — одни ошибки (§5).
@Test func accuracyPercentIsShownOutsideCourseOnly() {
    #expect(!ExerciseView.showsAccuracyPercent(mode: .course))
    #expect(ExerciseView.showsAccuracyPercent(mode: .adaptive))
    #expect(ExerciseView.showsAccuracyPercent(mode: .weak))
    #expect(ExerciseView.showsAccuracyPercent(mode: .practice))
}
