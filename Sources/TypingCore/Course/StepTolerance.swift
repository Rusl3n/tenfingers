import Foundation

/// Жёсткий допуск по ошибкам в шаге урока (фаза 8a, §3): шаг с большим числом ошибок не засчитывается.
public enum StepTolerance {
    /// Допустимое число ошибок: `max(3, длина × 4 / 100)`, целочисленно.
    public static func limit(length: Int) -> Int { max(3, length * 4 / 100) }

    /// Допуск действует на шаги обычных уроков; не действует на проверки урока (`check`, `refresh`)
    /// и на уроки-проверки этапа.
    public static func applies(kind: ExerciseKind, lessonKind: LessonKind) -> Bool {
        !kind.isLessonCheck && lessonKind != .stageCheck
    }

    public static func passed(errorCount: Int, length: Int) -> Bool { errorCount <= limit(length: length) }
}
