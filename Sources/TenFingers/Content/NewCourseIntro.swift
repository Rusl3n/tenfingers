import Foundation
import TypingCore

/// Лист «Новый курс» (2.0.0, §11): показывается один раз тем, у кого есть прогресс прежнего курса.
enum NewCourseIntro {
    /// Показать лист: флага нет и есть хоть одна строка `LessonProgress` издания 1.
    static func shouldShow(lessonIds: [String], defaults: UserDefaults) -> Bool {
        !defaults.bool(forKey: SettingsKey.newCourseIntroShown)
            && lessonIds.contains { CourseCatalog.edition(ofLessonId: $0) == 1 }
    }

    static func markShown(_ defaults: UserDefaults) {
        defaults.set(true, forKey: SettingsKey.newCourseIntroShown)
    }
}
