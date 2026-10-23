import Foundation
import Observation
import TypingCore

/// Курсы и генераторы текста, загружаемые один раз при старте.
@MainActor @Observable
final class ContentLibrary {
    private(set) var courses: [Language: Course] = [:]
    private(set) var planners: [Language: LessonPlanner] = [:]
    private(set) var loadError: String?

    init() {
        do {
            for language in Language.allCases {
                courses[language] = try CourseCatalog.load(language)
                planners[language] = LessonPlanner(generator: TextGenerator(wordList: try WordList.load(language)))
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
}
