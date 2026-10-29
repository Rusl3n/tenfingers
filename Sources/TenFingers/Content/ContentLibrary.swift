import Foundation
import Observation
import TypingCore

/// Курсы и генераторы текста, загружаемые один раз при старте.
@MainActor @Observable
final class ContentLibrary {
    private(set) var courses: [Language: Course] = [:]
    /// Курсы издания 1 (`course-<lang>-v1.json`, архив): названия и прогресс прежних уроков; нет файла — нет ключа.
    private(set) var legacyCourses: [Language: Course] = [:]
    private(set) var planners: [Language: LessonPlanner] = [:]
    /// Отрывки классики для практики.
    private(set) var texts: [Language: [LibraryText]] = [:]
    private(set) var loadError: String?

    init() {
        do {
            for language in Language.allCases {
                courses[language] = try CourseCatalog.load(language)
                legacyCourses[language] = try CourseCatalog.legacy(language)
                let library = try TextLibrary.load(language)
                texts[language] = library
                planners[language] = LessonPlanner(generator: TextGenerator(wordList: try WordList.load(language)),
                                                   corpus: try SentenceCorpus.load(language), library: library)
            }
        } catch CoreResourceError.missing(let file) {
            loadError = String(localized: "Не найден файл \(file)")
        } catch {
            loadError = String(describing: error)
        }
    }
}

struct LessonRun: Identifiable, Equatable {
    let id = UUID()
    let language: Language
    let lessonId: String
    /// Повтор одного шага урока по номеру в плане (`ExerciseSpec.id`): без знакомства и без продолжения урока.
    var onlyStepIndex: Int? = nil
}
