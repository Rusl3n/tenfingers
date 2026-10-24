import Testing
import TypingCore
@testable import TenFingers

/// Алерт замены скрытого запуска называет вид запуска, а не всегда «урок».
@Test func replaceAlertNamesTheRunKind() {
    let training = TrainingRun(language: .ru)
    let titles = [
        RunKind.lesson(LessonRun(language: .ru, lessonId: "ru.1.1")),
        .adaptive(training), .weakSpots(training),
        .practice(PracticeRun(language: .ru, source: .frequentWords)),
    ].map(\.replaceAlertTitle)
    #expect(titles[0].hasPrefix("Текущий урок"))
    #expect(titles[1].hasPrefix("Тренировка"))
    #expect(titles[2].hasPrefix("Слабые места"))
    #expect(titles[3].hasPrefix("Практика"))
    #expect(Set(titles).count == 4)
}
