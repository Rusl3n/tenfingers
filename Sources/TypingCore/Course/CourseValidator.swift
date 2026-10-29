// Проверка структуры курса издания 2 (спецификация фазы 6, §2.6): её зовут тесты каталога.

public enum CourseValidator {
    /// Между соседними «Повтором» и «Ускорением» (и от начала курса до первого) — не больше стольких уроков (§2.1).
    static let maxLessonsBetweenReviews = 6

    /// Нарушения структуры издания 2 (пусто — всё верно); `expectedKeys` — все клавиши курса языка.
    public static func problems(_ course: Course, expectedKeys: Set<Character>) -> [String] {
        var found: [String] = []
        let prefix = "\(course.language.rawValue)2"
        if course.edition != 2 { found.append("издание курса \(course.edition), ожидается 2") }
        if course.rows == nil { found.append("у курса нет рядов (rows)") }

        // 1. Id уроков и этапов.
        var seen: Set<String> = []
        for lesson in course.lessons {
            if !seen.insert(lesson.id).inserted { found.append("урок \(lesson.id) повторяется") }
            if !lesson.id.hasPrefix("\(prefix).") { found.append("урок \(lesson.id): id не начинается с «\(prefix).»") }
        }
        for (stageIndex, stage) in course.stages.enumerated() {
            let stageId = "\(prefix).s\(stageIndex + 1)"
            if stage.id != stageId { found.append("этап \(stage.id): ожидается id \(stageId)") }
            for (index, lesson) in stage.lessons.enumerated() {
                let number = index + 1 < 10 ? "0\(index + 1)" : "\(index + 1)"
                let expected = lesson.resolvedKind == .stageCheck ? "\(stageId).check" : "\(stageId).\(number)"
                if lesson.id != expected { found.append("урок \(lesson.id): ожидается id \(expected)") }
            }
        }

        // 2. Проверка этапа — последним уроком и одна; длина проверки задана.
        for stage in course.stages {
            let checks = stage.lessons.dropLast().filter { $0.resolvedKind == .stageCheck }
            if stage.lessons.last?.resolvedKind == .stageCheck {
                for lesson in checks { found.append("этап \(stage.id): лишняя проверка этапа \(lesson.id)") }
            } else if checks.isEmpty {
                found.append("этап \(stage.id): нет проверки этапа (stageCheck) последним уроком")
            } else {
                for lesson in checks { found.append("этап \(stage.id): проверка этапа \(lesson.id) стоит не последней") }
            }
            if stage.lengths?.check == nil { found.append("этап \(stage.id): нет длины проверки (lengths.check)") }
        }

        // 3. Поля уроков по виду.
        for lesson in course.lessons {
            switch lesson.resolvedKind {
            case .rows:
                let count = lesson.rows?.count ?? 0
                if !(1...3).contains(count) {
                    found.append("урок \(lesson.id): у урока рядов нужно 1–3 ряда, а их \(count)")
                }
                if let rows = lesson.rows, Set(rows).count != rows.count {
                    found.append("урок \(lesson.id): ряды повторяются")
                }
            case .tier:
                if lesson.targetCpm == nil { found.append("урок \(lesson.id): у ступени нет цели (targetCpm)") }
            case .keys:
                if lesson.newKeys.isEmpty && lesson.capitals != true && (lesson.focus ?? []).isEmpty {
                    found.append("урок \(lesson.id): у урока клавиш нет newKeys, capitals и focus")
                }
            case .review, .speedup, .text, .stageCheck:
                break
            }
        }

        // 3а. Число шагов урока (§2.2): 6–8, у проверки этапа — 3.
        for lesson in course.lessons {
            guard let ctx = course.context(for: lesson.id) else { continue }
            let count = StepTemplates.resolve(ctx).count
            let expected = lesson.resolvedKind == .stageCheck ? 3...3 : 6...8
            if !expected.contains(count) {
                let range = expected.count == 1 ? "\(expected.lowerBound)" : "\(expected.lowerBound)–\(expected.upperBound)"
                found.append("урок \(lesson.id): \(count) \(stepsWord(count)), ожидается \(range)")
            }
        }

        // 4. Каждая клавиша вводится один раз; вместе — ровно клавиши курса.
        var firstLesson: [Character: String] = [:]
        for lesson in course.lessons {
            for key in lesson.newCharacters {
                if let earlier = firstLesson[key] {
                    found.append("клавиша «\(key)» в уроке \(lesson.id) уже введена в уроке \(earlier)")
                } else {
                    firstLesson[key] = lesson.id
                }
            }
        }
        let taught = Set(firstLesson.keys)
        for key in expectedKeys.subtracting(taught).sorted() { found.append("клавиша «\(key)» не вводится в курсе") }
        for key in taught.subtracting(expectedKeys).sorted() {
            found.append("клавиша «\(key)» (урок \(firstLesson[key] ?? "")) не входит в клавиши курса")
        }

        // 5. «Повтор» и «Ускорение» чередуются с «Повтора», между ними не больше 6 уроков.
        var expectedKind = LessonKind.review
        var previous = -1
        for (position, lesson) in course.lessons.enumerated()
        where lesson.resolvedKind == .review || lesson.resolvedKind == .speedup {
            if lesson.resolvedKind != expectedKind {
                found.append("урок \(lesson.id): ожидается \(expectedKind == .review ? "«Повтор»" : "«Ускорение»")")
            }
            let between = position - previous - 1
            if between > maxLessonsBetweenReviews {
                found.append("урок \(lesson.id): до него \(between) уроков без «Повтора» и «Ускорения»")
            }
            expectedKind = lesson.resolvedKind == .review ? .speedup : .review
            previous = position
        }
        if previous < 0 && course.lessons.count > maxLessonsBetweenReviews {
            found.append("в курсе нет «Повтора» и «Ускорения», а уроков \(course.lessons.count)")
        }

        // 6. Порог и цели этапов.
        for stage in course.stages {
            if !(1...LessonScoring.maxStars).contains(stage.gate) {
                found.append("этап \(stage.id): порог \(stage.gate) вне 1…\(LessonScoring.maxStars)")
            }
            if stage.targetEnd < stage.targetCpm {
                found.append("этап \(stage.id): цель «до» \(stage.targetEnd) меньше «от» \(stage.targetCpm)")
            }
        }
        return found
    }

    /// «шаг», «шага», «шагов» по числу.
    private static func stepsWord(_ count: Int) -> String {
        let tens = count % 100, ones = count % 10
        if (11...14).contains(tens) { return "шагов" }
        switch ones {
        case 1: return "шаг"
        case 2...4: return "шага"
        default: return "шагов"
        }
    }
}
