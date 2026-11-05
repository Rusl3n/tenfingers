import Foundation
import TypingCore

/// Промежуточный экран шага: что показать при переборе ошибок (чистая модель, вью только рисует).
struct StepInterim: Equatable {
    let errors: Int
    /// `nil` — допуск на шаге не действует.
    let limit: Int?

    var overLimit: Bool { limit.map { errors > $0 } ?? false }
    var showsNext: Bool { !overLimit }
    var showsRetry: Bool { overLimit }
    var toleranceLine: String? {
        guard overLimit, let limit else { return nil }
        return String(localized: "Ошибок \(errors) — допустимо не больше \(limit)")
    }
}

/// Счётчик «ошибки N из M» во время набора.
enum ErrorCounter {
    static func text(errors: Int, limit: Int) -> String {
        String(localized: "Ошибки: \(errors) из \(limit)")
    }

    static func isOver(errors: Int, limit: Int) -> Bool { errors > limit }
}

/// Проход урока: шаги с перебором ошибок. К проверке (последнему шагу) не пускает, пока такие есть.
struct LessonPass: Equatable {
    private(set) var overLimit: Set<Int> = []

    mutating func record(step index: Int, passed: Bool) {
        if passed { overLimit.remove(index) } else { overLimit.insert(index) }
    }

    /// Проверка урока доступна, когда нет шагов с перебором.
    var checkAvailable: Bool { overLimit.isEmpty }

    /// Шаг, с которого запустить `requested`: до проверки — первый шаг с перебором.
    func entry(requested: Int, lastIndex: Int) -> Int {
        requested == lastIndex && !checkAvailable ? (overLimit.min() ?? requested) : requested
    }
}
