/// Все ачивки приложения (§12, §21). Порядок — порядок показа на экране.
/// Id стабильны: по ним хранятся полученные ачивки, переименовывать нельзя.
public enum AchievementCatalog {
    public static let all: [Achievement] =
        streak + speed + accuracy + course + volume + special + letters + fun

    private static let streak: [Achievement] = [
        Achievement(id: "streak.3", category: .streak, icon: "flame", condition: .streak(days: 3)),
        Achievement(id: "streak.7", category: .streak, icon: "flame.fill", condition: .streak(days: 7)),
        Achievement(id: "streak.14", category: .streak, icon: "calendar", condition: .streak(days: 14)),
        Achievement(id: "streak.30", category: .streak, icon: "calendar.badge.checkmark", condition: .streak(days: 30)),
        Achievement(id: "streak.50", category: .streak, icon: "star.circle.fill", condition: .streak(days: 50)),
        Achievement(id: "streak.100", category: .streak, icon: "medal.fill", condition: .streak(days: 100)),
        Achievement(id: "streak.200", category: .streak, icon: "rosette", condition: .streak(days: 200)),
        Achievement(id: "streak.365", category: .streak, icon: "crown.fill", condition: .streak(days: 365)),
        Achievement(id: "streak.iron_will", category: .streak, icon: "shield.lefthalf.filled",
                    condition: .fullStreakNoFreeze(days: 30)),
    ]

    private static let speedSteps: [(cpm: Int, icon: String)] = [
        (100, "hare"),
        (150, "gauge.with.dots.needle.33percent"),
        (200, "gauge.with.dots.needle.67percent"),
        (250, "wifi"),
        (300, "pianokeys"),
    ]

    private static let speed: [Achievement] = Language.allCases.flatMap { language in
        speedSteps.map { step in
            Achievement(id: "speed.\(language.rawValue).\(step.cpm)", category: .speed, icon: step.icon,
                        condition: .speed(language, cpm: step.cpm))
        }
    }

    private static let accuracy: [Achievement] = [
        Achievement(id: "accuracy.sniper", category: .accuracy, icon: "scope", condition: .perfectAccuracy),
        Achievement(id: "accuracy.surgeon", category: .accuracy, icon: "stethoscope",
                    condition: .accuracyRun(count: 10, minimum: 0.98)),
        Achievement(id: "accuracy.clean_day", category: .accuracy, icon: "sparkles",
                    condition: .cleanDay(exercises: 5, minimum: 0.97)),
    ]

    private static let course: [Achievement] = [
        Achievement(id: "course.first_lesson", category: .course, icon: "graduationcap", condition: .firstLesson),
        Achievement(id: "course.first_stage", category: .course, icon: "flag.checkered", condition: .firstStage),
        Achievement(id: "course.ru", category: .course, icon: "checkmark.seal.fill", condition: .courseCompleted(.ru)),
        Achievement(id: "course.en", category: .course, icon: "checkmark.seal", condition: .courseCompleted(.en)),
        Achievement(id: "course.polyglot", category: .course, icon: "globe", condition: .polyglot),
        Achievement(id: "course.stars.ru", category: .course, icon: "star.fill", condition: .allThreeStars(.ru)),
        Achievement(id: "course.stars.en", category: .course, icon: "star.square.fill", condition: .allThreeStars(.en)),
    ]

    private static let volume: [Achievement] = [
        Achievement(id: "volume.chars.10k", category: .volume, icon: "keyboard", condition: .volumeChars(10_000)),
        Achievement(id: "volume.chars.100k", category: .volume, icon: "doc.text", condition: .volumeChars(100_000)),
        Achievement(id: "volume.chars.1m", category: .volume, icon: "books.vertical.fill",
                    condition: .volumeChars(1_000_000)),
        Achievement(id: "volume.hours.1", category: .volume, icon: "clock", condition: .volumeHours(1)),
        Achievement(id: "volume.hours.10", category: .volume, icon: "clock.fill", condition: .volumeHours(10)),
        Achievement(id: "volume.hours.50", category: .volume, icon: "hourglass", condition: .volumeHours(50)),
        Achievement(id: "volume.hours.100", category: .volume, icon: "hourglass.bottomhalf.filled",
                    condition: .volumeHours(100)),
    ]

    private static let special: [Achievement] = [
        Achievement(id: "special.night_owl", category: .special, icon: "moon.stars.fill",
                    condition: .finishedBetween(startHour: 0, endHour: 4)),
        Achievement(id: "special.early_bird", category: .special, icon: "sunrise.fill",
                    condition: .finishedBetween(startHour: 6, endHour: 8)),
        Achievement(id: "special.no_peeking", category: .special, icon: "eye.slash", condition: .noKeyboard),
        Achievement(id: "special.steel_pinkies", category: .special, icon: "hand.raised.fingers.spread.fill",
                    condition: .steelPinkies(presses: 30)),
    ]

    private static func unlock(_ id: String, _ language: Language, _ letters: String, icon: String,
                                adult: Bool = false) -> Achievement {
        Achievement(id: "letters.\(language.rawValue).\(id)", category: .letters, icon: icon, adult: adult,
                    condition: .lettersUnlocked(language, Set(letters)), lettersDisplay: letters)
    }

    private static let letters: [Achievement] = [
        unlock("hello", .ru, "привет", icon: "hand.wave"),
        unlock("pizza", .ru, "пицца", icon: "fork.knife"),
        unlock("borscht", .ru, "борщ", icon: "carrot.fill"),
        unlock("b_word", .ru, "бля", icon: "exclamationmark.bubble", adult: true),
        unlock("three_letters", .ru, "хуй", icon: "pencil.and.scribble", adult: true),
        unlock("deadline", .ru, "жопа", icon: "clock.badge.exclamationmark", adult: true),
        unlock("yo", .ru, "ё", icon: "character.textbox"),
        unlock("hard_sign", .ru, "ъ", icon: "scroll"),
        Achievement(id: "letters.ru.alphabet", category: .letters, icon: "character.book.closed",
                    condition: .wholeAlphabet(.ru)),
        unlock("fluent_f", .en, "fuck", icon: "f.cursive", adult: true),
        unlock("shit_happens", .en, "shit", icon: "tornado", adult: true),
        unlock("wtf", .en, "wtf", icon: "exclamationmark.questionmark", adult: true),
        unlock("pizza", .en, "pizza", icon: "takeoutbag.and.cup.and.straw"),
        unlock("hello_world", .en, "helloworld", icon: "chevron.left.forwardslash.chevron.right"),
        unlock("sudo", .en, "sudo", icon: "terminal"),
        unlock("vim", .en, ":q!", icon: "door.left.hand.open"),
    ]

    private static let fun: [Achievement] = [
        Achievement(id: "fun.ghbdtn", category: .fun, icon: "arrow.left.arrow.right",
                    condition: .counter(name: "wrongLayoutStarts", threshold: 10)),
        Achievement(id: "fun.sausage_fingers", category: .fun, icon: "hand.thumbsdown", condition: .errorStreak(10)),
        Achievement(id: "fun.ctrl_z", category: .fun, icon: "arrow.uturn.backward", condition: .errorsInExercise(50)),
        Achievement(id: "fun.oy_vsyo", category: .fun, icon: "capslock.fill",
                    condition: .counter(name: "capsLockPresses", threshold: 1)),
        Achievement(id: "fun.perfectionist", category: .fun, icon: "arrow.counterclockwise",
                    condition: .lessonReplays(10)),
        Achievement(id: "fun.not_today", category: .fun, icon: "bed.double.fill", condition: .abandonsInDay(3)),
        Achievement(id: "fun.no_coffee", category: .fun, icon: "cup.and.saucer",
                    condition: .finishedBetween(startHour: 5, endHour: 6)),
        Achievement(id: "fun.new_year", category: .fun, icon: "party.popper", condition: .dayOfYear(month: 1, day: 1)),
        Achievement(id: "fun.friday13", category: .fun, icon: "calendar.badge.exclamationmark",
                    condition: .fridayThe13th),
        Achievement(id: "fun.bilingual", category: .fun, icon: "character.bubble", condition: .bilingualDay),
        Achievement(id: "fun.marathon", category: .fun, icon: "figure.run", condition: .marathonDay(minutes: 60)),
        Achievement(id: "fun.comeback", category: .fun, icon: "figure.wave", condition: .comeback(gapDays: 7)),
    ]
}
